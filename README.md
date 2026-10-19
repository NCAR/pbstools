# pbstools
A collection of user-facing PBS convenience tools maintained by CSG

## Description
These tools help augment basic PBS Pro commands with capabilities desired by the NCAR user community. Currently, the following tools are included:

* **qinteractive** - a script to quickly generate an interactive session
* **qcmd** - a script that allows the user to run a command in an output-only (*but otherwise fully functional*) shell to check something on a compute node, for example `make`,`nvidia-smi`, or `lscpu`.
* **launch_cf** - a script that allows users to submit "command files" easily using PBS job arrays [(documentation)](https://ncar-hpc-docs.readthedocs.io/en/latest/pbs/job-scripts/#using-job-arrays-to-launch-a-command-file).

The `qinteractive` script is also linked as `execcasper`, a variant that targets Casper by default.

## Installation

Simply clone this repository and add the tools to the users' PATH via some mechanism (e.g., an environment module).
```
git clone https://github.com/NCAR/pbstools.git
export PATH=/path/to/pbstools/bin:$PATH
```

The tools find their configuration (`etc/`, `util/`, `share/`) relative to their own location, after following symbolic links, so `bin/` can also be linked into another directory. They need:

* bash 4 or newer;
* the PBS Pro client commands (`qsub`, `qstat`, `qdel`);
* `NCAR_HOST` set to the current system, e.g. `derecho` or `casper`, as it is on NCAR login nodes.

## Usage

Each tool prints its full usage with `--help`.

### qinteractive and execcasper

`qinteractive` starts an interactive job (`qsub -I`) with sensible defaults for the system you are on. `execcasper` does the same, but on Casper wherever you run it.

```
qinteractive                              # the defaults for this system
qinteractive -l walltime=02:00:00         # any qsub option overrides a default
qinteractive --ntasks 4 --mem 20GB        # short resource flags, below
qinteractive -q main@desched1             # another queue, and system
execcasper --ngpus 1                      # a Casper session with one GPU
```

If a display is available, X forwarding (`-X`) is turned on automatically.

### qcmd

`qcmd` runs a single command as a batch job and streams its output back to your terminal as it runs, as if it ran locally. It has no interactive terminal; use `qinteractive` for that.

```
qcmd -- make -j 8                         # build on a compute node
qcmd --ntasks 4 -- mpirun ./my_program    # options before "--", the command after it
qcmd --logpath=build.log -- make -j 8     # also save the output to build.log
```

* Everything after `--` is the command, which runs in the current directory, with your current environment (`qsub -V`).
* `qcmd` exits with the command's exit status.
* Pressing Ctrl-C deletes the job.
* While the job runs, its script and output are kept in `~/.qcmd/`, and removed afterwards. `--debug` keeps the script.

### Options shared by qinteractive, execcasper and qcmd

Any standard `qsub` option can be given, and overrides the corresponding default. The tools also accept these short flags, which build the `-l select=` resource request for you:

| Flag | Sets, per chunk |
|---|---|
| `--nchunks N` | the number of chunks (nodes) |
| `--ncpus N` | CPUs |
| `--ntasks N` | MPI tasks (`mpiprocs`) |
| `--nthreads N` | OpenMP threads (`ompthreads`) |
| `--mem SIZE` | memory, e.g. `20GB` |
| `--ngpus N` | GPUs |
| `--cpu TYPE` | CPU type (`cpu_type`) |
| `--gpu TYPE` | GPU type (`gpu_type`) |

If `--ncpus` isn't given, it is `--ntasks` × `--nthreads`. The short flags describe one kind of chunk; for a heterogeneous job, give your own `-l select=`.

Other options:

* **`--show`**: prints the `qsub` command that would be run, without submitting it.
* **`--help`**: prints the usage, with the defaults for the chosen system.
* **`@SYSTEM`**, e.g. `@casper`: uses that system's defaults. So does `-q QUEUE@SERVER`. See [Systems](#systems).

**Account.** The project to charge is, in order of precedence:

1. `-A PROJECT` on the command line;
2. `PBS_ACCOUNT_<HOST>`, for the system you are logged in to, e.g. `PBS_ACCOUNT_DERECHO` or `PBS_ACCOUNT_CASPER`;
3. `DAV_PROJECT`, for jobs on Casper;
4. `PBS_ACCOUNT`.

If none is set, the tool stops with an error.

**Defaults.** Without any options, the tools request:

| System | Queue | Resources | Walltime |
|---|---|---|---|
| Derecho | `develop` | 32 CPUs, 55 GB | 1 hour |
| Derecho, other queues (e.g. `-q main`) | as given | a full node: 128 CPUs, 235 GB | 1 hour |
| Casper | `casper` | 1 CPU, 10 GB | 6 hours for `qinteractive` and `execcasper`, 1 hour for `qcmd` |

With `--ngpus`, the GPU type defaults to `a100` on Derecho. On Casper it defaults to `vis` for one GPU and `cc70` for more. Derecho's `develop` queue also scales CPUs and memory with the number of GPUs. The full set of defaults is in each system's file in [`etc/`](etc/).

### launch_cf

`launch_cf` runs the commands in a *command file*, one per line, packing them onto nodes and submitting them as a PBS job array. See the [NCAR documentation](https://ncar-hpc-docs.readthedocs.io/en/latest/pbs/job-scripts/#using-job-arrays-to-launch-a-command-file) for a full walk-through.

```
launch_cf -A PROJECT -l walltime=1:00:00                     # runs ./cmdfile
launch_cf -A PROJECT -l walltime=1:00:00 ./my_cmdfile
launch_cf -A PROJECT -l walltime=1:00:00 --nthreads 4 --steps-per-node 32 ./omp_cmdfile
launch_cf -A PROJECT -l walltime=4:00:00 --nodes 4 ./my_cmdfile    # spread the steps over 4 nodes
launch_cf -A PROJECT -l walltime=1:00:00 --dryrun ./my_cmdfile   # write the job script, don't submit it
launch_cf -A PROJECT -l walltime=1:00:00 --rerun 1234567          # resubmit the steps of job 1234567 that didn't succeed
```

**The command file**

* Each line is one step, run from the submission directory.
* Lines starting with `#` are comments and are skipped, as are blank lines. A step can end with a `# comment`.
* If `./config_env.sh` exists, it is sourced before the steps run, e.g. for `module load` commands.

**Options**

`-A` and `-l walltime=` are required. Any option `launch_cf` doesn't recognize is passed to PBS.

| Option | Meaning | Derecho default | Casper default |
|---|---|---|---|
| `-q`, `--queue QUEUE` | queue; `casper@casper-pbs` or `main@desched1` submits to the other system, using its defaults | `main` | `casper` |
| `--ppn`, `--processors-per-node N` | CPUs per node (Casper: at most 36) | 128 | 1 |
| `--steps-per-node N` | steps each node runs; any beyond CPUs ÷ threads run in waves | CPUs ÷ threads | CPUs ÷ threads |
| `--nodes N` | spread the steps evenly over N nodes, instead of giving `--steps-per-node` | | |
| `--nthreads`, `--threads-per-step N` | OpenMP threads per step | 1 | 1 |
| `--mem`, `--memory SIZE` | memory per node | `235G` | `10G` |
| `--cpu_type TYPE` | CPU type | | |
| `--random_start_delay SECONDS` | wait up to this long, at random, before starting each step | 0 | 0 |
| `--script FILE` | name of the generated job script | `./launch_cf.<command file>.<timestamp>.pbs` | |
| `--rerun JOBID` | submit the steps of an earlier job that didn't succeed; see below | | |
| `--dryrun`, `--dry-run` | write the job script and report what it requests, but don't submit it | | |

`-J` and `-l select=` are worked out from the steps and options above, so they can't be given.

**Steps per node and waves**

Each node runs up to CPUs ÷ threads steps at once. A node can be given more steps than that, with `--steps-per-node` or `--nodes`. It then starts its next step each time a running one finishes, so its steps run in *waves*. For example, 1200 steps on Derecho with `--nodes 4` give each node 300 steps, which run 128 at a time in 3 waves.

* **Allow walltime for every wave.** `launch_cf` can't know how long the steps take, but it reports how many waves each node runs. Request enough walltime for that many steps in a row.
* **Unless you give `--ppn`, each node gets enough CPUs to run all of its steps at once**, up to a full node. This matters on Casper, where the default is one CPU. With `--ppn`, each node runs only as many steps at once as fit in those CPUs.
* **Each step's exit status** is reported in the array element's output file when the step finishes.

**Rerunning the steps that didn't succeed**

`launch_cf --rerun JOBID` finds the steps of an earlier `launch_cf` job that didn't succeed, and submits just those. Run it from the directory that job was submitted from, once it has finished. For example:

```
$ launch_cf -A PROJECT -l walltime=0:10:00 --rerun 6285048
Job 6285048: 1 of 1200 steps did not succeed:
  step 332 of job 6285048: never ran: subjob 331 did not run
Wrote ./cmdfile.6285048.rerun, to submit as the command file.
...
```

* **A step succeeded only if its array element reported it finishing with exit status 0.** So it catches steps that exited with an error, and steps of an array element that was cut short (walltime, memory, preemption). It also catches steps of an element that never ran at all, e.g. because PBS rejected it on its node.
* **The steps are written to a new command file**, `./<command file>.<JOBID>.rerun`, with a comment saying why each is rerun, then submitted like any other. Use `--dryrun` to see the list without submitting it.
* **The other options aren't taken from the earlier job.** Give `-A`, `-l walltime=` and any others again, and choose `--steps-per-node` or `--nodes` for the smaller number of steps.
* **Each step keeps its `${step}`** from the original job, so steps that use it, e.g. to name their output, write the same files. `--rerun` of a rerun job works the same way.
* **Jobs run with an older `launch_cf`** don't record their command file, so give it as well: `launch_cf ... --rerun JOBID ./cmdfile`. Jobs from before steps reported their exit status can't be rerun this way.

**What it produces**

* **A self-contained job script**, written to the current directory and then submitted. Every resource request is an ordinary `#PBS` line, so you can inspect it, edit it, and resubmit it with plain `qsub` without running `launch_cf` again.
* **One output file per array element**, `<job name>.o<job id>.<index>`, listing the steps it launched, and when each finished with its exit status. The job name is `launch_cf` unless you set `-N`.
* **Each step's output**, in `stdout-<job id>/step-NNNNN.out`.

If every step fits on one node, the job is submitted without an array, since PBS doesn't allow one-element arrays.

## Systems
System configurations are provided in the `etc` subdirectory of this repository. They are used by `qinteractive`, `execcasper` and `qcmd`. See the existing configurations for reference. The names provided in there will be used by the tools when "@" syntax is provided by the user. For example:
```
qinteractive -q main@gust
```
would use settings in a file called `etc/gust.conf`. It is recommended that you provide both short-form names and the explicit scheduler server name as options, likely via symbolic links.

The current configurations are:

| File | Links to it |
|---|---|
| `derecho.conf` | `desched1.conf`, `desched2.conf`, `gust.conf` (which in turn has `gusched1.conf` and `gusched2.conf`) |
| `casper.conf` | `casper-pbs.conf`, `dav.conf` |

A configuration is a bash fragment, sourced after the options are parsed. It sets:

* **`pbs_server`**: the PBS server to submit to.
* **`pbs_opts[...]`**: the default queue (`-q`), walltime and `-l select` additions, which may depend on the queue and requested GPUs.
* **`def_ncpus`**, **`max_cpus`**, **`def_gpu`**: the default and maximum CPUs per chunk, and the default GPU type.
* **`res_type`**: a description of the default resources, shown by `--help`.
* **`acc_var_dep`** (optional): a further environment variable to take the project from, e.g. `DAV_PROJECT` on Casper.

`launch_cf` doesn't use these files: its Derecho and Casper defaults are set in `bin/launch_cf` itself.

## Repository layout

| Path | Contents |
|---|---|
| `bin/` | the tools: `qinteractive`, `execcasper` (a link to it), `qcmd` and `launch_cf` |
| `etc/` | system configurations for `qinteractive`, `execcasper` and `qcmd` |
| `util/parse_opts` | option parsing shared by `qinteractive`, `execcasper` and `qcmd` |
| `util/mod_init.sh` | module initialization for job environments, from a former `qsub` wrapper; not currently used |
| `share/launch_cf.pbs` | the job script template `launch_cf` builds on |
| `tests/` | tests for `launch_cf` and `qcmd` |

## Testing

See [tests/README.md](tests/README.md). In short, from `tests/` on a Derecho or Casper login node:

```
make check              # submit this system's launch_cf tests
./check_results.sh      # once the jobs finish: PASSED, FAILED or NOT FINISHED
```

Or, anywhere, without submitting jobs:

```
make check_dryrun && ./check_results.sh dryrun
```
