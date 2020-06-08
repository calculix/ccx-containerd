# CalculiX CrunchiX Containered
Reference Implementation to build an docker compatible container for Calculix / CrunchiX (ccx).
The buildah script contains also all commands that are needed to manipulate the original sources to fix knowing issues.

> **Warning:** Active deployment

### HowTo use the container
In general it is recommended to create an shell script with all commands and start the container with the script file as argument.

Befor execute an command from the container, please execute the command (bash shell)
```console
. ~/ccx_env
```
to set all the envoriment variables for the Calculix ChruniX to the default values.


### Running the container (with podman)
 - Example to print all set envoriment variables
```console
podman run --rm --volume $PWD:/data calculix/ccx:latest test/print_env
```

 - Execute / run an input file *MyCaseFile.inp* from the actually directory and remove the container afterwards.
```console
podman run --rm --volume $PWD:/data calculix/ccx:latest crunchix MyCaseFile
```

 - Run bash (interactive mode + allocate tty) inside the container.
```console
podman run --rm -i -t --volume $PWD:/data calculix/ccx:latest /bin/bash
```

### Envoriment variables
 - **CCX_VERSION**
 Compiled ccx version.
 - **CCX_INSTALL_DIR**
 Installation directory of ccx.
 - **CCX_ARPACK_DIR**
 Source directory of ARPACK package.
 - **CCX_SPOOLES_DIR**
 Source directory of SPOOLES package.
 - **CCX_SRC**
 Source directory of ccx.
 - **CCX_DOC**
 Documentation directory of ccx.
 - **CCX_TEST**
 All test scripts for ccx.

***
[CalculiX - A Three-Dimensional Structural Finite Element Program](http://www.calculix.de/)
