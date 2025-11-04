#!/bin/bash
#
#   Simple collection of qcmd tests for both systems
#
#   Last Revised:   23:50, 03 Nov 2025
#

if [[ $# -gt 1 ]]; then
    if [[ -f $1/qinteractive ]]; then
        export PATH=$1:$PATH
    else
        >&2 echo "Error: path given does not provide utilities ($1)"
        exit 1
    fi
fi

function run_test {
    echo "Running qcmd with arguments = $1"
    timeout 60s qcmd $1 -- mpirun hostname
    echo
}

echo -e "\n=== RUNNING ${NCAR_HOST^^} TESTS ===\n"

if [[ $NCAR_HOST == derecho ]]; then
    run_test ""
    run_test "-l select=2:ncpus=1:mpiprocs=1:mem=10GB -q develop"
    run_test "-q main"
    run_test "-l select=1:ncpus=4:ngpus=4:gpu_type=a100"
    run_test "-l select=1:ncpus=4:ngpus=4 -l gpu_type=a100"
elif [[ $NCAR_HOST == casper ]]; then
    run_test "--gpu vis --ngpus 1"
    run_test "-l select=1:ncpus=1:ngpus=1:gpu_type=cc70"
    run_test "-l select=2:ncpus=1"
    run_test "-l select=1:ncpus=1:ngpus=1"
    run_test "-l select=1:ncpus=1:ngpus=1 -l gpu_type=l40"
    run_test "-l select=1:ncpus=1:ngpus=1:gpu_model=v100"
    run_test "--cpu skylake"
    run_test ""
else
    >& echo "Error: unknown NCAR_HOST == $NCAR_HOST"
    exit 1
fi
