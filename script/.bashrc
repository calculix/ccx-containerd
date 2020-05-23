#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

#
export OMP_NUM_THREADS=$(nproc)
export CCX_NPROC_EQUATION_SOLVER=$(nproc)
export CCX_NPROC_RESULTS=$(nproc)
export NUMBER_OF_CPUS=$(nproc)

