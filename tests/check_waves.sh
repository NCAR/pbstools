#!/bin/bash

#----------------------------------------------------------------------------
# Test how launch_cf runs a node's steps in waves, without a scheduler
# ("make check_waves").
#
# Generates launch_cf job scripts with --dryrun, and runs them here as PBS
# would, with a fake ${PBS_NODEFILE}.  The command file has 12 steps, run 4
# at a time on one node, so in 3 waves.  The first step of each wave is short
# and the others long, so the two ways of running waves differ:
#   * by default, the node starts its next step as soon as a slot is free, so
#     the second wave starts while most of the first still runs;
#   * with --sync-waves, each wave starts only once every step of the wave
#     before it has finished.
#
# Exit status: 0 = all checks passed, 1 = at least one failed
#----------------------------------------------------------------------------

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
launch_cf="${launch_cf:-${SCRIPTDIR}/../bin/launch_cf}"
export NCAR_HOST=derecho

workdir="${SCRIPTDIR}/waves"
rm -rf "${workdir}" && mkdir -p "${workdir}" && cd "${workdir}" || exit 1

npass=0; nfail=0
check ()
{
    local label="${1}"; shift
    if "${@}"; then
        printf ' %-6s %s\n' "[PASS]" "${label}"; npass=$((npass + 1))
    else
        printf ' %-6s %s\n' "[FAIL]" "${label}"; nfail=$((nfail + 1))
    fi
}

#------------------------------------------------------------------
# run the generated script ${1} as PBS job ${2}, a single job (not an array),
# with the mpiprocs and ompthreads its select line requests.
run_job ()
{
    local script="${1}" seq="${2}" mpiprocs threads
    mpiprocs=$(sed -n 's/^#PBS -l select=.*:mpiprocs=\([0-9]*\).*/\1/p' "${script}")
    threads=$(sed -n 's/^#PBS -l select=.*:ompthreads=\([0-9]*\).*/\1/p' "${script}")
    yes "node1.test" | head -n ${mpiprocs} > ./nodefile.${seq}
    env -u PBS_ARRAY_INDEX -u PBS_ARRAY_ID PBS_NODEFILE=./nodefile.${seq} OMP_NUM_THREADS=${threads} \
        PBS_JOBID="${seq}.test" bash "${script}" > launch_cf.o${seq} 2>&1
}

# from the output of job ${1}, which runs ${2} steps at once, print:
#   <steps launched> <steps finished with status 0> <most running at once>
#   <waves started while a step of the wave before still ran>
# reading the launch and finish reports in the order the job wrote them.
summarize ()
{
    awk -v at_once=${2} '
        / launching step [0-9]+:/ {
            if (n > 0 && n % at_once == 0 && running > 0) early++
            n++
            if (++running > maxrun) maxrun = running
        }
        / finished  step [0-9]+: exit status / { running--; if ($NF == 0) ok++ }
        END { printf "%d %d %d %d\n", n, ok, maxrun, early }' "${1}"
}

#------------------------------------------------------------------
# 12 steps: in each group of 4, a short step and 3 long ones.
for i in $(seq 1 12); do
    if [ $(( (i - 1) % 4 )) -eq 0 ]; then
        echo "sleep 0.2 # step ${i}"
    else
        echo "sleep 1.5 # step ${i}"
    fi
done > ./cmdfile

for mode in pool sync; do
    seq=1001; opts=""
    [ ${mode} = sync ] && { seq=1002; opts="--sync-waves"; }
    ${launch_cf} -A TEST -l walltime=0:10:00 --ppn 4 --steps-per-node 12 ${opts} --dryrun \
        --script ./job${seq}.pbs ./cmdfile > ./launch_cf.${seq}.log 2>&1
done

echo "running job 1001 (12 steps, 4 at once, in 3 waves) ..."
run_job ./job1001.pbs 1001
echo "running job 1002 (the same, with --sync-waves) ..."
run_job ./job1002.pbs 1002
echo

read -r n ok maxrun early <<< "$(summarize ./launch_cf.o1001 4)"
check "default: all 12 steps ran and succeeded"                  [ "${n} ${ok}" = "12 12" ]
check "default: at most 4 steps ran at once"                     [ ${maxrun} -le 4 ]
check "default: a slot is refilled before the whole wave is done" [ ${early} -gt 0 ]
check "default: the job does not report synchronized waves"      [ -z "$(grep '^waves: synchronized' ./launch_cf.o1001)" ]

check "--sync-waves: launch_cf reports it"                       grep -q "With --sync-waves, each wave starts only once" ./launch_cf.1002.log
check "--sync-waves: it is baked into the job script"            grep -q '^sync_waves="${sync_waves:-yes}"$' ./job1002.pbs
read -r n ok maxrun early <<< "$(summarize ./launch_cf.o1002 4)"
check "--sync-waves: all 12 steps ran and succeeded"             [ "${n} ${ok}" = "12 12" ]
check "--sync-waves: each wave used all 4 slots, and no more"    [ ${maxrun} -eq 4 ]
check "--sync-waves: no wave started before the one before it finished" [ ${early} -eq 0 ]
check "--sync-waves: the job reports synchronized waves"         grep -q '^waves: synchronized' ./launch_cf.o1002
check "--sync-waves: the job reports starting waves 1, 2 and 3" \
    [ "$(grep -o 'starting  wave [0-9]* of [0-9]*' ./launch_cf.o1002 | tr '\n' ',')" = "starting  wave 1 of 3,starting  wave 2 of 3,starting  wave 3 of 3," ]

# the setting can be overridden at submit time, e.g. "qsub -v sync_waves=no"
echo
echo "running job 1002 again, with sync_waves=no ..."
sync_waves=no run_job ./job1002.pbs 1003
read -r n ok maxrun early <<< "$(summarize ./launch_cf.o1003 4)"
check "sync_waves=no overrides --sync-waves" [ "${n} ${ok}" = "12 12" -a ${early} -gt 0 ]

echo
if [ ${nfail} -gt 0 ]; then
    echo "Result: FAILED (${npass} passed, ${nfail} failed); see the logs in ${workdir}"
    exit 1
fi
echo "Result: PASSED (all ${npass} checks)"
exit 0
