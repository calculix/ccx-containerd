#!/bin/bash -xe

##
# Script to build an container for Calculix / CrunchiX (ccx)
#
# This file also contains an reference implementation of the build steps
# for the ccx software.
#
# Example usage:
#
#  - execute / run an input file from actually directory
#    podman run --volume $PWD:/data calculix/ccx:latest crunchix myInputFile
#
#  - run bash with interative mode in container
#    podman run --volume $PWD:/data -i -t calculix/ccx:latest /bin/bash
#
# Knowing issues:
#  - ARPACK library does not support multi threading build (make -j option).
#    Thomas Enzinger, 22.05.2020
#


# parse command line
TAUCS_ENABLED=0

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --TAUCS) TAUCS_ENABLED=1 ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done


# parse git branch to dected the compiling version
[ -n "$SOURCE_BRANCH" ]  || SOURCE_BRANCH=$(git symbolic-ref -q --short HEAD)
if [[ "$SOURCE_BRANCH" == "master" ]]; then
        SOURCE_BRANCH="latest"
        VERSION=2.16
elif [[ "$SOURCE_BRANCH" == "dev" ]]; then
        SOURCE_BRANCH="dev"
        VERSION="dev"
elif [[ "${SOURCE_BRANCH/-v*/}" =~ ^[0-9][0-9.]*$ ]]; then
        VERSION=${SOURCE_BRANCH/-v*/}
else
        SOURCE_BRANCH=$(echo $SOURCE_BRANCH | sed 's/^[A-Za-z]*//g')
        if [[ "${SOURCE_BRANCH/-*/}" =~ ^[0-9][0-9.]*$ ]]; then
                VERSION=${SOURCE_BRANCH/-*/}
        else
                echo "ERROR: Source Branch not found"
                exit -1;
        fi
fi

[ -n "$IMAGE_PREFIX" ]       || IMAGE_PREFIX=calculix
[ -n "$IMAGE_APPNAME" ]      || IMAGE_APPNAME=ccx
[ -n "$IMAGE_NAME" ]         || IMAGE_NAME=${IMAGE_PREFIX}/${IMAGE_APPNAME}:${SOURCE_BRANCH}


# Create a container
newc=$(buildah from --format=docker fedora:latest)


# install basic software
buildah run $newc /bin/bash -c "                                                   \
     dnf update -y                                                                 \
  && dnf groupinstall -y 'Development Tools'                                       \
  && dnf install -y                                                                \
       sudo bash bash-completion                                                   \
       gcc-c++ gcc-gfortran                                                        \
       openmpi openmpi-devel                                                       \
  && dnf clean all && rm -rf /var/cache/dnf                                        \
  "


# config entry
CC=gcc
FC=gfortran
CCX_INSTALL_DIR="/usr/local/CalculiX/ccx_${VERSION}"

buildah config                                                                     \
  --env "VERSION=$VERSION"                                                         \
  --env "CCX_VERSION=$VERSION"                                                     \
  --env "CC=$CC"                                                                   \
  --env "FC=$FC"                                                                   \
  --env "CCX_INSTALL_DIR=$CCX_INSTALL_DIR"                                         \
  --env "CCX_ARPACK_DIR=/usr/local/ARPACK"                                         \
  --env "CCX_SPOOLES_DIR=/usr/local/SPOOLES.2.2"                                   \
  --env "CCX_SRC=$CCX_INSTALL_DIR/src"                                             \
  --env "CCX_DOC=$CCX_INSTALL_DIR/doc"                                             \
  --env "CCX_TEST=$CCX_INSTALL_DIR/test"                                           \
  $newc


# username, group, and a lot of settings
fname=calculix

buildah run $newc useradd --shell /bin/bash --create-home -U $fname

buildah copy $newc script/bashrc "/home/$fname/.bashrc"
buildah copy $newc script/set_cpu_count "/home/$fname/set_cpu_count"
buildah copy $newc script/ccx_env "/home/$fname/ccx_env"
buildah copy $newc script/crunchix "/usr/local/bin/crunchix"

buildah run $newc /bin/bash -c "                                                   \
     echo '$fname ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers                          \
  && echo '127.0.1.1  localhost' >> /etc/hosts                                     \
  && echo '::1        localhost' >> /etc/hosts                                     \
  && echo 'export VERSION=$VERSION' >> /home/$fname/.bashrc                        \
  && echo 'export CCX_VERSION=$VERSION' >> /home/$fname/.bashrc                    \
  && echo 'export CC=$CC' >> /home/$fname/.bashrc                                  \
  && echo 'export FC=$FC' >> /home/$fname/.bashrc                                  \
  && echo 'export CCX_INSTALL_DIR=/usr/local/CalculiX/ccx_${VERSION}' >> /home/$fname/.bashrc \
  && echo 'export CCX_ARPACK_DIR=/usr/local/ARPACK' >> /home/$fname/.bashrc        \
  && echo 'export CCX_SPOOLES_DIR=/usr/local/SPOOLES.2.2' >> /home/$fname/.bashrc  \
  && echo 'export CCX_SRC=$CCX_INSTALL_DIR/src' >> /home/$fname/.bashrc            \
  && echo 'export CCX_DOC=$CCX_INSTALL_DIR/doc' >> /home/$fname/.bashrc            \
  && echo 'export CCX_TEST=$CCX_INSTALL_DIR/test' >> /home/$fname/.bashrc          \
  && echo '[[ $- != *i* ]] && return' >> /home/$fname/.bashrc                      \
  && chown $fname:$fname /home/$fname/.bashrc                                      \
  && chmod +x /home/$fname/.bashrc                                                 \
  && chown $fname:$fname /home/$fname/set_cpu_count                                \
  && chown $fname:$fname /home/$fname/ccx_env                                      \
  "


# get git repository
[ -d repo ] && rm -rf repo
mkdir -p repo
git clone https://github.com/calculix/ccx.git ./repo
git --git-dir=./repo/.git --work-tree=./repo checkout "v$VERSION"


# copy sources
buildah copy $newc repo/src    "/usr/local/CalculiX/ccx_${VERSION}/src/"
buildah copy $newc repo/doc    "/usr/local/CalculiX/ccx_${VERSION}/doc/"
buildah copy $newc repo/test   "/usr/local/CalculiX/ccx_${VERSION}/test/"

buildah copy $newc repo/3rdpart/ARPACK/arpack96.tar.Z    '/usr/local/'
buildah copy $newc repo/3rdpart/ARPACK/patch.tar.Z       '/usr/local/'

buildah copy $newc repo/3rdpart/SPOOLES/spooles.2.2.tgz  '/usr/local/SPOOLES.2.2/'
buildah copy $newc repo/3rdpart/SPOOLES/2.2_patch        '/usr/local/SPOOLES.2.2/2.2_patch/'

rm -rf repo


# ccx2paraview
[ -d ccx2paraview ] && rm -rf ccx2paraview
mkdir -p ccx2paraview
git clone https://github.com/calculix/ccx2paraview.git ./ccx2paraview
cd ccx2paraview
pyinstaller --onefile src/ccx2paraview.py --hidden-import 'packaging.requirements' --hidden-import 'pkg_resources.py2_warn'
cd ..
buildah copy $newc ccx2paraview/dist/ccx2paraview        '/usr/local/bin/ccx2paraview'
rm -rf ccx2paraview


# unv2ccx
[ -d unv2ccx ] && rm -rf unv2ccx
mkdir -p unv2ccx
git clone https://github.com/calculix/unv2ccx.git ./unv2ccx
cd unv2ccx
pyinstaller --onefile unv2ccx.py
cd ..
buildah copy $newc unv2ccx/dist/unv2ccx                  '/usr/local/bin/unv2ccx'
rm -rf unv2ccx


# arpack
buildah run $newc /bin/bash -c                                                     \
  "  . /home/$fname/.bashrc                                                        \
  && cd /usr/local                                                                 \
  && tar -xvzf arpack96.tar.Z                                                      \
  && tar -xvzf patch.tar.Z                                                         \
  && rm -f arpack96.tar.Z patch.tar.Z                                              \
  && cd /usr/local/ARPACK                                                          \
  && sed -i 's/^FC.*=.*/FC      = $FC/'               ARmake.inc                   \
  && sed -i 's/^FFLAGS.*=.*/FFLAGS  = -O2/'           ARmake.inc                   \
  && sed -i 's/^PLAT.*=.*/PLAT = INTEL/'              ARmake.inc                   \
  && sed -i 's|^home.*=.*|home = /usr/local/ARPACK|'  ARmake.inc                   \
  && sed -i 's/^      EXTERNAL           ETIME/*&/'   UTIL/second.f                \
  && make lib                                                                      \
  && find . -name '*.o' -delete                                                    \
  "


# SPOOLES
buildah run $newc /bin/bash -c "                                                   \
     . /home/$fname/.bashrc                                                        \
  && cd /usr/local/SPOOLES.2.2/                                                    \
  && tar -xvzf spooles.2.2.tgz                                                     \
  && /bin/cp -rf 2.2_patch/* . && rm -Rf 2.2_patch                                 \
  && sed -i 's/^ .*CC.*=.*/  CC = $CC/' Make.inc                                   \
  && sed -i 's/^ .*OPTLEVEL.*=.*/  OPTLEVEL = -O2/' Make.inc                       \
  && sed -i 's/^ .*THREAD_LIBS.*=.*/  THREAD_LIBS = -lpthread/' Make.inc           \
  && sed -i 's|^ .*MPI_INSTALL_DIR.*=.*|  MPI_INSTALL_DIR = /usr/lib64/openmpi/|' Make.inc             \
  && sed -i 's|^ .*MPI_LIB_PATH.*=.*|  MPI_LIB_PATH = -L$(MPI_INSTALL_DIR)/lib|' Make.inc              \
  && sed -i 's|^ .*MPI_INCLUDE_DIR.*=.*|  MPI_INCLUDE_DIR = -I/usr/include/openmpi-x86_64/|' Make.inc  \
  && sed -i '/^#.*/s/^#/\t/g' makefile                                             \
  && sed -i 's/drawTree.c \\\\/draw.c \\\\/g' Tree/src/makeGlobalLib               \
  && make -j$(nproc) lib                                                           \
  "


# taucs
if [ "$TAUCS_ENABLED" -eq 1 ] ; then
  #
  buildah run $newc /bin/bash -c "                                                 \
       dnf install -y                                                              \
         lapack-static atlas-static metis metis-devel                              \
    && dnf clean all && rm -rf /var/cache/dnf                                      \
    "
  #
  [ -d "taucs" ] && rm -rf taucs
  mkdir taucs
  tar -xzvf 3rdpart/taucs/taucs_2.2.tgz -C taucs
  buildah copy $newc taucs "/usr/local/taucs/"
  rm -rf taucs
  #
  buildah run $newc /bin/bash -c "                                                 \
       cd /usr/local/taucs                                                         \
    && ./configure                                                                 \
    && touch build/linux/taucs_config_tests.h                                      \
    && echo '#define TAUCS_BLAS_UNDERSCORE' >> build/linux/taucs_config_tests.h    \
    && echo '#define TAUCS_C99_COMPLEX' >> build/linux/taucs_config_tests.h        \
    && sed -i 's|^FC        = g77|FC        = gfortran|' config/linux.mk           \
    && sed -i 's| -Wall||' config/linux.mk                                         \
    && sed -i 's| -Werror||' config/linux.mk                                       \
    && sed -i 's| -pedantic||' config/linux.mk                                     \
    && sed -i 's|LIBBLAS   = -L external/lib/linux|LIBBLAS   = -L /usr/lib64/atlas|' config/linux.mk \
    && sed -i 's|LIBLAPACK = -L external/lib/linux|LIBLAPACK = -L /usr/lib|' config/linux.mk \
    && sed -i 's|LIBF77 = -lg2c|LIBF77 = -lgfortran|' config/linux.mk              \
    && make -j$(nproc)                                                             \
    && cd /usr/local/CalculiX/ccx_${VERSION}/src                                   \
    && sed -i 's|^CFLAGS = .*|& -I ../../../taucs/src -I ../../../taucs/build/linux -DTAUCS |'  Makefile_MT \
    && sed -i 's|^LIBS = \.*|& ../../../taucs/lib/linux/libtaucs.a /usr/lib64/atlas/liblapack.a /usr/lib64/atlas/libf77blas.a /usr/lib64/atlas/libcblas.a /usr/lib64/atlas/libatlas.a|'  Makefile_MT \
    && sed -i 's|$(FC) -fopenmp|& -lgfortran -lmetis|' Makefile_MT                 \
    "
  #-lf77blas -lcblas -latlas -llapack -lmetis
#    && echo '#define TAUCS_BLAS_F2C' >> build/linux/taucs_config_tests.h           \
fi


# Calculix
buildah run $newc /bin/bash -c "                                                   \
     . /home/$fname/.bashrc                                                        \
  && cd /usr/local/CalculiX/ccx_${VERSION}/src                                     \
  && sed -i 's/^CC=.*/CC=$CC/'                        Makefile_MT                  \
  && sed -i 's/^FC=.*/FC=$FC/'                        Makefile_MT                  \
  && make -j$(nproc) -f Makefile_MT                                                \
  && chmod a+rx ccx_${VERSION}_MT                                                  \
  && ln -s /usr/local/CalculiX/ccx_${VERSION}/src/ccx_${VERSION}_MT /usr/local/bin/ccx                 \
  && find . -name '*.o' -delete                                                    \
  && find . -name '*.a' -delete                                                    \
  "

# clean taucs .o files
if [ "$TAUCS_ENABLED" -eq 1 ] ; then

buildah run $newc /bin/bash -c "                                                   \
     cd /usr/local/taucs                                                           \
  && find . -name '*.o' -delete                                                    \
  "
fi

# config entry
buildah config                                                                     \
  --user "$fname:$fname"                                                           \
  --shell "/bin/bash -c"                                                           \
  --volume '/data'                                                                 \
  --workingdir '/data'                                                             \
  --label maintainer='Thomas Enzinger <info@thomas-enzinger.de>'                   \
  --author='Thomas Enzinger'                                                       \
  $newc

# Finally saves the running container to an image
newi=$(buildah commit --rm --format docker $newc $IMAGE_NAME)

