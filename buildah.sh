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
#    podman run --volume $PWD:/data calculix/ccx:latest ccx myInputFile.inp
#
#  - run bash with interative mode in container
#    podman run --volume $PWD:/data -i -t calculix/ccx:latest /bin/bash
#
# Knowing issues:
#  - ARPACK library does not support multi threading build (make -j option).
#    Thomas Enzinger, 22.05.2020
#


# parse git branch to dected the compiling version
[ -n "$SOURCE_BRANCH" ]  || SOURCE_BRANCH=$(git symbolic-ref -q --short HEAD)
if [[ "$SOURCE_BRANCH" == "master" ]]; then
        SOURCE_BRANCH="latest"
        VERSION=2.16
elif [[ "$SOURCE_BRANCH" == "dev" ]]; then
        SOURCE_BRANCH="dev"
        VERSION="dev"
elif [[ "${SOURCE_BRANCH/-*/}" =~ ^[0-9][0-9.]*$ ]]; then
        VERSION=${SOURCE_BRANCH/-*/}
else
        echo "ERROR: Source Branch not found"
        exit -1;
fi

[ -n "$IMAGE_PREFIX" ]       || IMAGE_PREFIX=calculix
[ -n "$IMAGE_APPNAME" ]      || IMAGE_APPNAME=ccx
[ -n "$IMAGE_NAME" ]         || IMAGE_NAME=${IMAGE_PREFIX}/${IMAGE_APPNAME}:${SOURCE_BRANCH}


# Create a container
newc=$(buildah from --format=docker fedora:latest)


# install basic software
buildah run $newc /bin/bash -c                                                     \
  "  dnf update -y                                                                 \
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

buildah config                                                                     \
  --env "VERSION=$VERSION"                                                         \
  --env "CC=$CC"                                                                   \
  --env "FC=$FC"                                                                   \
  $newc


# username, group, and a lot of settings
fname=calculix

buildah run $newc /bin/bash -c                                                     \
  " useradd --shell /bin/zsh --create-home -U $fname                               \
  && echo '$fname ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers                          \
  && echo '127.0.1.1 $(hostname)' >> /etc/hosts                                    \
  && echo 'include /usr/share/nano/*' >> /home/$fname/.nanorc                      \
  && chown "$fname:$fname" /home/$fname/.nanorc                                    \
  && echo 'export OMP_NUM_THREADS=\$(nproc)' >> /home/$fname/.bashrc               \
  && echo 'export CCX_NPROC_EQUATION_SOLVER=\$(nproc)' >> /home/$fname/.bashrc     \
  && echo 'export CC=$CC' >> /home/$fname/.bashrc                                  \
  && echo 'export FC=$FC' >> /home/$fname/.bashrc                                  \
  && chown "$fname:$fname" /home/$fname/.bashrc"


# get git repository
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
buildah run $newc /bin/bash -c                                                     \
  "  . /home/$fname/.bashrc                                                        \
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


# Calculix
buildah run $newc /bin/bash -c                                                     \
  "  . /home/$fname/.bashrc                                                        \
  && cd /usr/local/CalculiX/ccx_${VERSION}/src                                     \
  && sed -i 's/^CC=.*/CC=$CC/'                        Makefile_MT                  \
  && sed -i 's/^FC=.*/FC=$FC/'                        Makefile_MT                  \
  && make -j$(nproc) -f Makefile_MT                                                \
  && chmod a+rx ccx_${VERSION}_MT                                                  \
  && ln -s /usr/local/CalculiX/ccx_${VERSION}/src/ccx_${VERSION}_MT /usr/local/bin/ccx                 \
  && find . -name '*.o' -delete                                                    \
  && find . -name '*.a' -delete                                                    \
  "


# config entry
buildah config                                                                     \
  --user "$fname:$fname"                                                           \
  --volume '/data'                                                                 \
  --workingdir '/data'                                                             \
  --label maintainer='Thomas Enzinger <info@thomas-enzinger.de>'                   \
  --author='Thomas Enzinger'                                                       \
  $newc

# Finally saves the running container to an image
buildah commit --rm --format docker $newc $IMAGE_NAME