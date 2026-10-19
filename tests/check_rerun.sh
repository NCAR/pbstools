#!/bin/bash

#----------------------------------------------------------------------------
# Test "launch_cf --rerun" without a scheduler ("make check_rerun").
#
# Generates launch_cf job scripts with --dryrun, and runs their subjobs here
# as PBS would, with a fake ${PBS_NODEFILE}.  The first job has a step that
# exits with an error, a subjob that never runs, and a subjob killed part way
# through.  The test checks that --rerun picks out exactly the steps that did
# not succeed, that the rerun steps keep their original ${step}, and that
# --rerun of the rerun job picks out the steps that failed again.
#
# Exit status: 0 = all checks passed, 1 = at least one failed
#----------------------------------------------------------------------------

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
launch_cf="${launch_cf:-${SCRIPTDIR}/../bin/launch_cf}"
export NCAR_HOST=derecho

workdir="${SCRIPTDIR}/rerun"
rm -rf "${workdir}" && mkdir -p "${workdir}" && cd "${workdir}" || exit 1

# a stand-in for qstat, so that the test does not depend on what the system's
# qstat says about these made-up jobs: every job has finished, except
# ${fake_running_job}, which is reported running.
mkdir -p ./bin
cat > ./bin/qstat <<'EOF'
#!/bin/bash
for id; do :; done
if [ -n "${fake_running_job}" ] && [[ "${id}" == "${fake_running_job}"[.[]* ]]; then
    printf 'Job Id: %s\n    job_state = R\n' "${id}"
    exit 0
fi
echo "qstat: Unknown Job Id ${id}" >&2
exit 153
EOF
chmod +x ./bin/qstat
export PATH="$(pwd)/bin:${PATH}"
unset fake_running_job

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
# run subjob ${3} of the generated script ${1} as PBS job ${2}, with
# the mpiprocs and ompthreads its select line requests.
run_subjob ()
{
    local script="${1}" seq="${2}" idx="${3}" mpiprocs threads
    mpiprocs=$(sed -n 's/^#PBS -l select=.*:mpiprocs=\([0-9]*\).*/\1/p' "${script}")
    threads=$(sed -n 's/^#PBS -l select=.*:ompthreads=\([0-9]*\).*/\1/p' "${script}")
    yes "node1.test" | head -n ${mpiprocs} > ./nodefile.${seq}
    PBS_NODEFILE=./nodefile.${seq} OMP_NUM_THREADS=${threads} PBS_JOBID="${seq}.test" \
        PBS_ARRAY_ID="${seq}[].test" PBS_ARRAY_INDEX=${idx} \
        bash "${script}" > launch_cf.o${seq}.${idx} 2>&1
}

# as above, but kill the subjob and its steps after ${4} seconds, as PBS
# would at the end of its walltime.
run_subjob_killed ()
{
    local pid
    set -m      # its own process group, so that its steps are killed too
    run_subjob "${1}" "${2}" "${3}" &
    pid=$!
    set +m
    sleep ${4}
    kill -TERM -- -${pid} 2>/dev/null
    wait ${pid} 2>/dev/null
}

# the steps of a rerun command file, as "step=N; command" lines
rerun_steps () { grep -v '^#' "${1}" | sed 's/[[:space:]]*#.*//'; }

#------------------------------------------------------------------
# 20 steps, 4 per node with 2 at once, so 5 subjobs.
#   step 7 exits with status 3; subjob 2 (steps 9-12) never runs;
#   subjob 4 (steps 17-20) is killed while step 18 still runs.
#   step 10 records its ${step}, which counts from 0.
for i in $(seq 1 20); do
    case ${i} in
        7)  echo "echo seven; exit 3 # step ${i}" ;;
        10) echo "echo \${step} > step10.out # step ${i}" ;;
        18) echo "sleep 60 # step ${i}" ;;
        *)  echo "echo step ${i} # step ${i}" ;;
    esac
done > ./cmdfile

echo "running job 1001 (20 steps, subjob 2 never runs, subjob 4 killed) ..."
${launch_cf} -A TEST -l walltime=0:10:00 --ppn 2 --steps-per-node 4 --dryrun --script ./job1001.pbs ./cmdfile > ./launch_cf.1001.log 2>&1
for idx in 0 1 3; do run_subjob ./job1001.pbs 1001 ${idx}; done
: > launch_cf.o1001.2       # PBS rejected it: an empty output file
run_subjob_killed ./job1001.pbs 1001 4 3

echo "launch_cf --rerun 1001 ..."
${launch_cf} -A TEST -l walltime=0:10:00 --ppn 6 --steps-per-node 6 --rerun 1001 --dryrun --script ./job1002.pbs > ./rerun.1001.log 2>&1
status=$?
echo
check "--rerun 1001 succeeds" [ ${status} -eq 0 ]
[ ${status} -eq 0 ] || sed 's/^/        /' ./rerun.1001.log | head -20
check "it writes ./cmdfile.1001.rerun" [ -f ./cmdfile.1001.rerun ]

expected="step=6; echo seven; exit 3
step=8; echo step 9
step=9; echo \${step} > step10.out
step=10; echo step 11
step=11; echo step 12
step=17; sleep 60"
check "it reruns exactly steps 7, 9-12 and 18" [ "$(rerun_steps ./cmdfile.1001.rerun)" = "${expected}" ]
check "step 7: exited with status 3"      grep -q "^# step 7 of job 1001: exited with status 3, see stdout-1001.test/step-00007.out" ./cmdfile.1001.rerun
check "steps 9-12: subjob 2 did not run"  [ "$(grep -c "never ran: subjob 2 did not run" ./cmdfile.1001.rerun 2>/dev/null)" = 4 ]
check "step 18: cut short"                grep -q "^# step 18 of job 1001: cut short: subjob 4 stopped while it ran" ./cmdfile.1001.rerun
check "the job submits the rerun file"    grep -q "^#   command file    : .*/cmdfile.1001.rerun$" ./job1002.pbs

#------------------------------------------------------------------
# the rerun job: 6 steps on one node, all at once.  Step 7 fails again and
# step 18 is cut short again; the others succeed.
echo
echo "running job 1002, the rerun ..."
run_subjob_killed ./job1002.pbs 1002 0 3
mv launch_cf.o1002.0 launch_cf.o1002        # a single job, not an array
check "step 10 keeps its \${step} (9)" [ "$(cat ./step10.out 2>/dev/null)" = "9" ]

${launch_cf} -A TEST -l walltime=0:10:00 --rerun 1002 --dryrun --script ./job1003.pbs > ./rerun.1002.log 2>&1
expected="step=6; echo seven; exit 3
step=17; sleep 60"
check "--rerun 1002 reruns just steps 7 and 18 again" [ "$(rerun_steps ./cmdfile.1002.rerun 2>/dev/null)" = "${expected}" ]

#------------------------------------------------------------------
# a job whose steps all succeeded, and other cases --rerun refuses
echo
echo "running job 1004 (3 steps, all succeed) ..."
printf 'echo a\necho b\necho c\n' > ./ok_cmdfile
${launch_cf} -A TEST -l walltime=0:10:00 --dryrun --script ./job1004.pbs ./ok_cmdfile > /dev/null 2>&1
run_subjob ./job1004.pbs 1004 0
mv launch_cf.o1004.0 launch_cf.o1004        # a single job, not an array
${launch_cf} -A TEST -l walltime=0:10:00 --rerun 1004 --dryrun > ./rerun.1004.log 2>&1
status=$?
check "--rerun of a job that succeeded: nothing to rerun" grep -q "nothing to rerun" ./rerun.1004.log
check "... exits 0 and writes nothing" [ ${status} -eq 0 -a ! -f ./ok_cmdfile.1004.rerun ]

${launch_cf} -A TEST -l walltime=0:10:00 --rerun 9999 --dryrun > ./rerun.9999.log 2>&1
status=$?
ok=no; [ ${status} -ne 0 ] && grep -q "no PBS output files of job 9999" ./rerun.9999.log && ok=yes
check "--rerun of an unknown job fails" [ ${ok} = yes ]

fake_running_job=1004 ${launch_cf} -A TEST -l walltime=0:10:00 --rerun 1004 --dryrun > ./rerun.running.log 2>&1
status=$?
ok=no; [ ${status} -ne 0 ] && grep -q "is still queued or running (state R)" ./rerun.running.log && ok=yes
check "--rerun refuses a job that is still running" [ ${ok} = yes ]

echo 'echo d' >> ./ok_cmdfile
${launch_cf} -A TEST -l walltime=0:10:00 --rerun 1004 --dryrun > ./rerun.changed.log 2>&1
status=$?
ok=no; [ ${status} -ne 0 ] && grep -q "no longer has the 3 steps" ./rerun.changed.log && ok=yes
check "--rerun refuses a command file that has changed" [ ${ok} = yes ]

echo
if [ ${nfail} -gt 0 ]; then
    echo "Result: FAILED (${npass} passed, ${nfail} failed); see the logs in ${workdir}"
    exit 1
fi
echo "Result: PASSED (all ${npass} checks)"
exit 0
