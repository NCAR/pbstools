
# (an absolute path, since each suite runs from its own subdirectory)
launch_cf ?= $(CURDIR)/../bin/launch_cf
account ?= SCSG0001

all: gs_openmp omp_cmdfile

gs_openmp: gs_openmp.c
	gcc -O2 -o $@ $< -fopenmp

gs_openmp.c:
	rm -f $@
	wget https://raw.githubusercontent.com/benkirk/paradigms_playground/master/gs_openmp.c

omp_cmdfile: Makefile
	echo "# sample cmdfile for an OpenMP application" > $@.tmp
	for i in $$(seq 1 510); do \
	  echo "./gs_openmp $$((1024*8*2)) # step $${i}" >> $@.tmp ; \
	done
	mv $@.tmp $@

# more steps than a node runs at once, so each node runs them in waves.  The
# steps take 5 to 14 seconds each, so that they finish out of order.
waves_cmdfile: Makefile
	echo "# sample cmdfile with steps of different lengths" > $@.tmp
	for i in $$(seq 1 300); do \
	  echo "sleep $$(( (i*7) % 10 + 5 )) # step $${i}" >> $@.tmp ; \
	done
	mv $@.tmp $@

hello_world_openmp: hello_world_openmp.C
	g++ -O2 -o $@ $< -fopenmp

hw_cmdfile: hello_world_openmp Makefile
	echo "# sample cmdfile for an OpenMP application" > $@.tmp
	for i in $$(seq 1 6); do \
	  echo "./$< # step $${i}" >> $@.tmp ; \
	done
	mv $@.tmp $@

# each suite runs from its own subdirectory, which collects the output of its
# jobs.  The command files and executables they run are shared, linked in from here.
suite_files := cmdfile smalltest omp_cmdfile hw_cmdfile waves_cmdfile gs_openmp hello_world_openmp
setup_suite_dir = mkdir -p $(1) && for f in $(suite_files); do ln -sf ../$$f $(1)/$$f; done

check_derecho: gs_openmp omp_cmdfile hw_cmdfile waves_cmdfile
	$(call setup_suite_dir,derecho)
	cd derecho && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 # check defaults
	cd derecho && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 ./smalltest # njobs < ppn
	cd derecho && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --nthreads 4 --steps-per-node 32 ./omp_cmdfile # openmp test
	cd derecho && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --nthreads 32 --steps-per-node 2 ./hw_cmdfile # openmp test
	cd derecho && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 -q casper@casper-pbs --ppn 32 --nthreads 4 -N derecho2casper_openmp_test ./omp_cmdfile # openmp test, derecho cross submission
	cd derecho && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --processors-per-node 128 --nthreads 8 --steps-per-node 16 --memory 100G --queue preempt --cpu_type milan --random_start_delay 5 -N all_args_test ./omp_cmdfile # all args
	cd derecho && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --steps-per-node 200 ./waves_cmdfile # 200 steps/node, 128 at once
	cd derecho && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --nodes 2 --nthreads 4 ./waves_cmdfile # 150 steps/node, 32 at once

check_casper: gs_openmp omp_cmdfile hw_cmdfile waves_cmdfile
	$(call setup_suite_dir,casper)
	cd casper && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 # check defaults
	cd casper && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 ./smalltest # njobs < ppn
	cd casper && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --nthreads 4 --steps-per-node 8 ./omp_cmdfile # openmp test
	cd casper && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 -q main@desched1 --nthreads 4 -N casper2derecho_openmp_test ./omp_cmdfile # openmp test, derecho cross submission
	cd casper && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --ppn 8 --steps-per-node 40 ./waves_cmdfile # 40 steps/node, 8 at once
	cd casper && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --nodes 3 ./waves_cmdfile # 100 steps/node, 36 at once (a full node)
#	cd casper && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --processors-per-node 32 --nthreads 8 --steps-per-node 4 --memory 300G --queue casper --cpu_type cascadelake --random_start_delay 5 -N all_args_test ./omp_cmdfile # all args

check: check_$(NCAR_HOST)

# remove everything the check_derecho / check_casper jobs wrote.
clean_derecho clean_casper:
	rm -rf ./$(subst clean_,,$@)

# scheduler-free check: exercise the argument handling and generate the PBS
# scripts for inspection, without submitting anything.  The expected values
# are Derecho's, wherever this runs.  "./check_results.sh dryrun" compares
# the scripts with the saved copies in ./dryrun_expected.
check_dryrun: export NCAR_HOST := derecho
check_dryrun:
	rm -rf ./dryrun && mkdir -p ./dryrun
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --dryrun --script ./dryrun/defaults.pbs # defaults, implicit ./cmdfile
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --dryrun --script ./dryrun/smalltest.pbs ./smalltest # njobs < ppn
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --nthreads 4 --steps-per-node 32 --dryrun --script ./dryrun/omp.pbs ./cmdfile # openmp test
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --nthreads 7 --steps-per-node 18 --dryrun --script ./dryrun/partial.pbs ./cmdfile # steps/node does not fill the node
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --nthreads 8 --steps-per-node 16 -l job_priority=economy -N all_args_test --random_start_delay 5 --dryrun --script ./dryrun/all_args.pbs ./cmdfile # pass-through args, -N override
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --steps-per-node 384 --dryrun --script ./dryrun/waves.pbs ./cmdfile # 384 steps/node, in 3 waves
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --nodes 5 --nthreads 4 --dryrun --script ./dryrun/nodes.pbs ./cmdfile # spread over 5 nodes, in 8 waves
	@echo && echo "generated scripts:" && ls -1 ./dryrun/

# scheduler-free check of "launch_cf --rerun": runs launch_cf job scripts
# here, as PBS would, and checks the steps --rerun picks out to run again.
check_rerun:
	./check_rerun.sh

# after an intended change to the generated scripts: review the differences
# reported by "./check_results.sh dryrun", then replace the saved copies.
save_dryrun: check_dryrun
	./check_results.sh --save dryrun
