#!/bin/bash

#----------------------------------------------------------------------------
# Summarize the results of "make check_derecho" or "make check_casper", and
# report whether the tests passed.
#
# Run it once the jobs submitted by "make check_<host>" have finished.  Each
# test is identified by what its job reports in its PBS output file (job name,
# total steps, steps/node, threads/step).  When a test was run more than once,
# the most recent job is the one checked.
#
# Exit status: 0 = all tests passed
#              1 = at least one test failed
#              2 = nothing failed, but some tests have not (fully) run yet
#----------------------------------------------------------------------------

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

#------------------------------------------------------------------
usage ()
{
    cat <<EOF
${0} <-h|--help> <derecho|casper> <results dir>

Checks the jobs submitted by "make check_derecho" or "make check_casper".
The test suite defaults to \${NCAR_HOST}, just like "make check", and the
results dir defaults to the suite's subdirectory of ${SCRIPTDIR},
where its tests are submitted from.
EOF
}

#------------------------------------------------------------------
# the tests in each suite, mirroring the check_derecho & check_casper
# targets in ./Makefile -- keep the two in sync.
#   label | PBS job name | command file | steps/node | threads/step
# steps/node "all" means every step fits on one node (a single, non-array job).
expected_tests ()
{
    case "${1}" in
        "derecho")
            cat <<EOF
defaults|launch_cf|cmdfile|128|1
njobs < ppn|launch_cf|smalltest|all|1
openmp|launch_cf|omp_cmdfile|32|4
openmp hello world|launch_cf|hw_cmdfile|2|32
derecho -> casper|derecho2casper_openmp_test|omp_cmdfile|8|4
all args|all_args_test|omp_cmdfile|16|8
EOF
            ;;
        "casper")
            cat <<EOF
defaults|launch_cf|cmdfile|1|1
njobs < ppn|launch_cf|smalltest|1|1
openmp|launch_cf|omp_cmdfile|8|4
casper -> derecho|casper2derecho_openmp_test|omp_cmdfile|32|4
EOF
            ;;
    esac
}

# output in a step log that means the step itself failed
step_error_pattern='command not found|No such file or directory|Segmentation fault|core dumped|Killed|error while loading shared libraries|Permission denied|Illegal instruction|Bus error|Out of memory|oom-kill'

#------------------------------------------------------------------
# bash function to count lines not beginning with "#" from a text file
# (exactly as launch_cf does)
count_non_comment_non_empty_lines ()
{
    i=0
    while read line; do
        # skip comment lines beginning with "#" and empty lines
        [[ ${line:0:1} == "#" || -z "${line// }" ]] && continue || i=$((i + 1))
    done < "${1}"
    echo ${i}
    return 0
}

#------------------------------------------------------------------
# one tab-separated record per PBS output file in the current directory,
# newest first:
#   name seq rank idx N spn thr done nerr steps first_error file took
# (fields not reported by the job are "-")
scan_outputs ()
{
    ls -t 2>/dev/null | grep -E '\.o[0-9]+(\.[0-9]+)?$' | awk '
    BEGIN { OFS = "\t" }
    {
        f = $0
        # <job name>.o<sequence number>, plus .<array index> for subjobs
        match(f, /\.o[0-9]+(\.[0-9]+)?$/)
        name = substr(f, 1, RSTART-1)
        np = split(substr(f, RSTART+2), p, ".")
        seq = p[1]
        idx = (np > 1) ? p[2] : "-"

        N = "-"; spn = "-"; thr = "-"; done = 0; nerr = 0; steps = ""; err = "-"; took = 0
        while ((getline line < f) > 0) {
            if (index(line, "(#steps/node) x (#threads/step) = ") == 1) {
                split(substr(line, 35), t, " x ")
                spn = t[1] + 0
                thr = (t[2] == "") ? "?" : t[2] + 0
            }
            if (match(line, /^n_total_steps: [0-9]+/))
                N = substr(line, 16, RLENGTH-15) + 0
            if (line ~ /^n_total_steps: / && match(line, /PBS_ARRAY_INDEX=[0-9]+/))
                idx = substr(line, RSTART+16, RLENGTH-16) + 0
            if (match(line, / launching step [0-9]+:/))
                steps = steps "," (substr(line, RSTART+16, RLENGTH-17) + 0)
            if (line ~ /^Done: PBS_ARRAY_INDEX=/) {
                done = 1
                if (match(line, /took [0-9]+ seconds/))
                    took = substr(line, RSTART+5, RLENGTH-13) + 0
            }
            if (line ~ /^ERROR|Cannot locate requested command file|Failed to get|job killed/) {
                nerr++
                if (err == "-") err = line
            }
        }
        close(f)
        if (idx == "-") idx = 0
        print name, seq, NR, idx, N, spn, thr, done, nerr, (steps == "" ? "-" : steps), err, f, took
    }'
}

#------------------------------------------------------------------
# print one test result, and tally it
report ()
{
    local status="${1}" label="${2}" detail="${3}" p
    printf ' [%s] %-20s %s\n' "${status}" "${label}" "${detail}"
    for p in "${problems[@]}"; do
        printf '        - %s\n' "${p}"
    done
    case "${status}" in
        "PASS") npass=$((npass + 1)) ;;
        "FAIL") nfail=$((nfail + 1)) ;;
        *)      nwait=$((nwait + 1)) ;;
    esac
}

#------------------------------------------------------------------
check_test ()
{
    local label="${1}" name="${2}" cf="${3}" spn="${4}" thr="${5}"
    local N nsub seq others detail logdir d
    local nfiles nmiss notdone nd_file nerr err took miss smiss sdup
    problems=()

    [ -r "${cf}" ] || { problems=( "cannot read ./${cf}; was \"make check_${suite}\" run from ${results_dir}?" ); report FAIL "${label}" ""; return; }
    N=$(count_non_comment_non_empty_lines "${cf}")
    [ "${spn}" = "all" ] && spn=${N}
    nsub=$(( (N + spn - 1) / spn ))

    # the newest job that ran this test (records are newest first)
    read -r seq others <<< "$(awk -F'\t' -v name="${name}" -v N=${N} -v spn=${spn} -v thr=${thr} '
        $1 == name && $5 == N && $6 == spn && $7 == thr && !($2 in seen) {
            seen[$2] = 1; n++; if (best == "") best = $2
        }
        END { print (best == "" ? "-" : best), (n > 0 ? n-1 : 0) }' "${records}")"

    if [ "${seq}" = "-" ]; then
        report WAIT "${label}" "no output yet from a ${name} job running ${N} steps as ${spn} steps/node x ${thr} threads (still queued or running?)"
        return
    fi
    selected_jobs+=( "${name}.o${seq}" )

    # summarize all of this job's output files
    IFS=$'\t' read -r nfiles nmiss notdone nd_file nerr err took miss smiss sdup <<< "$(awk -F'\t' -v name="${name}" -v seq=${seq} -v N=${N} -v nsub=${nsub} '
        $1 == name && $2 == seq {
            nfiles++; have[$4] = 1
            if (!$8) { notdone++; if (nd_file == "") nd_file = $12 }
            if ($9 > 0) { nerr += $9; if (err == "") err = $12 ": " $11 }
            if ($13 + 0 > took) took = $13 + 0
            n = split($10, s, ",")
            for (i = 1; i <= n; i++) if (s[i] != "" && s[i] != "-") cnt[s[i] + 0]++
        }
        END {
            for (i = 0; i < nsub; i++)
                if (!(i in have)) { nmiss++; if (nmiss <= 5) miss = miss (miss == "" ? "" : ",") i }
            if (nmiss > 5) miss = miss ",..."
            for (i = 1; i <= N; i++) { if (!(i in cnt)) smiss++; else if (cnt[i] > 1) sdup++ }
            printf "%d\t%d\t%d\t%s\t%d\t%s\t%d\t%s\t%d\t%d\n", nfiles, nmiss, notdone, (nd_file == "" ? "-" : nd_file),
                nerr, (err == "" ? "-" : err), took, (miss == "" ? "-" : miss), smiss, sdup
        }' "${records}")"

    detail="job ${seq} (${name}): $((nsub - nmiss))/${nsub} subjobs, ${N} steps, ${spn} steps/node x ${thr} threads/step, longest subjob ${took}s"
    [ ${others} -gt 0 ] && detail="${detail}, ${others} older run(s) ignored"

    # problems reported by the subjobs themselves
    [ ${nerr} -gt 0 ]    && problems+=( "${nerr} error(s) in the PBS output, first: ${err}" )
    [ ${notdone} -gt 0 ] && problems+=( "${notdone} subjob(s) did not finish (no \"Done:\" line), e.g. ${nd_file}" )
    [ ${sdup} -gt 0 ]    && problems+=( "${sdup} step(s) were launched more than once" )

    # the per-step logs
    logdir=""
    for d in "stdout-${seq}" stdout-${seq}.*; do
        [ -d "${d}" ] && { logdir="${d}"; break; }
    done
    if [ -n "${logdir}" ]; then
        bad=( $(grep -l -E "${step_error_pattern}" "${logdir}"/step-*.out 2>/dev/null) )
        [ ${#bad[@]} -gt 0 ] && problems+=( "${#bad[@]} step log(s) show errors, e.g. ${bad[0]}: \"$(grep -m1 -E "${step_error_pattern}" "${bad[0]}")\"" )

        # every hello world step should report the requested thread count
        if [ "${cf}" = "hw_cmdfile" ]; then
            bad=( $(grep -L "running with ${thr} threads" "${logdir}"/step-*.out 2>/dev/null) )
            [ ${#bad[@]} -gt 0 ] && problems+=( "${#bad[@]} step log(s) do not report \"running with ${thr} threads\", e.g. ${bad[0]}" )
        fi
    fi

    # completeness can only be judged once every subjob has reported
    if [ ${nmiss} -eq 0 ]; then
        [ ${smiss} -gt 0 ] && problems+=( "${smiss} of ${N} steps were never launched" )
        if [ -z "${logdir}" ]; then
            problems+=( "step log directory stdout-${seq}* not found" )
        else
            nlogs=$(ls "${logdir}" | awk -v N=${N} '
                /^step-[0-9]+\.out$/ { have[substr($0, 6, length($0) - 9) + 0] = 1 }
                END { for (i = 1; i <= N; i++) if (i in have) n++; print n + 0 }')
            [ ${nlogs} -lt ${N} ] && problems+=( "only ${nlogs} of ${N} step logs found in ${logdir}" )
        fi
    fi

    if [ ${#problems[@]} -gt 0 ]; then
        report FAIL "${label}" "${detail}"
    elif [ ${nmiss} -gt 0 ]; then
        problems=( "no output yet from subjob(s) ${miss} (still queued or running?)" )
        report WAIT "${label}" "${detail}"
    else
        report PASS "${label}" "${detail}"
    fi
}

#------------------------------------------------------------------
# a job of this suite that exited before reporting its layout cannot be
# matched to a test, so it would otherwise go unnoticed.  Report those newer
# than the oldest job checked above (all of them, if none were found).
check_unidentified ()
{
    local names oldest
    names=$(expected_tests ${suite} | cut -d'|' -f2 | sort -u | tr '\n' ' ')
    oldest=$(awk -F'\t' -v jobs=" ${selected_jobs[*]} " '
        index(jobs, " " $1 ".o" $2 " ") && $3 > max { max = $3 }
        END { print (max == "" ? 0 : max) }' "${records}")

    awk -F'\t' -v names=" ${names}" -v oldest=${oldest} '
        index(names, " " $1 " ") && $5 == "-" && (oldest == 0 || $3 < oldest) && !(($1 ".o" $2) in seen) {
            seen[$1 ".o" $2] = 1
            print $12 ": " ($11 == "-" ? "no launch_cf output" : $11)
        }' "${records}"
}

#------------------------------------------------------------------
# main execution follows...
suite="${1:-${NCAR_HOST}}"
results_dir="${2}"

case "${suite}" in
    "-h"|"--help")
        usage; exit 0 ;;
    "derecho"|"casper")
        ;;
    "check_derecho"|"check_casper")
        suite="${suite#check_}" ;;
    "")
        echo "ERROR: no test suite given, and \${NCAR_HOST} is not set"; usage; exit 1 ;;
    *)
        echo "ERROR: unknown test suite \"${suite}\", expected derecho or casper"; usage; exit 1 ;;
esac

[ -z "${results_dir}" ] && results_dir="${SCRIPTDIR}/${suite}"
cd "${results_dir}" || { echo "ERROR: cannot access results dir ${results_dir}"; exit 1; }

records=$(mktemp "${TMPDIR:-/tmp}/check_results.XXXXXX") || exit 1
trap 'rm -f "${records}"' EXIT
scan_outputs > "${records}"

echo "launch_cf test results: check_${suite}, in $(pwd)"
echo

npass=0; nfail=0; nwait=0
selected_jobs=()
while IFS='|' read -r label name cf spn thr <&3; do
    check_test "${label}" "${name}" "${cf}" "${spn}" "${thr}"
done 3< <(expected_tests ${suite})

unidentified=$(check_unidentified)
if [ -n "${unidentified}" ]; then
    echo
    echo " [FAIL] job(s) that exited before reporting which test they ran"
    echo "        (if these are left over from an earlier run, remove them and re-check):"
    echo "${unidentified}" | sed 's/^/        - /'
    nfail=$((nfail + 1))
fi

echo
if [ ${nfail} -gt 0 ]; then
    echo "Result: FAILED (${npass} passed, ${nfail} failed, ${nwait} not finished)"
    exit 1
elif [ ${nwait} -gt 0 ]; then
    echo "Result: NOT FINISHED (${npass} passed, ${nwait} not finished)"
    exit 2
fi
echo "Result: PASSED (all ${npass} tests)"
exit 0
