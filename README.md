# CalculiX CrunchiX Containered
Reference Implementation to build an docker compatible container for Calculix / CrunchiX (ccx).
The buildah script contains also all commands that are needed to manipulate the original sources to fix knowing issues.

### Running the container (with podman)
 - Execute / run an input file from actually directory and remove the container afterwards.
 ```bash podman run --rm --volume $PWD:/data calculix/ccx:latest ccx myInputFile.inp ```
 - Run bash (interactive mode + allocate tty) inside the container.
 ```bash podman run --volume $PWD:/data -i -t calculix/ccx:latest /bin/bash ```


***
[CalculiX - A Three-Dimensional Structural Finite Element Program](http://www.calculix.de/)
