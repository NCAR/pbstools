
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
suite_files := cmdfile smalltest omp_cmdfile hw_cmdfile gs_openmp hello_world_openmp
setup_suite_dir = mkdir -p $(1) && for f in $(suite_files); do ln -sf ../$$f $(1)/$$f; done

check_derecho: gs_openmp omp_cmdfile hw_cmdfile
	$(call setup_suite_dir,derecho)
	cd derecho && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 # check defaults
	cd derecho && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 ./smalltest # njobs < ppn
	cd derecho && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --nthreads 4 --steps-per-node 32 ./omp_cmdfile # openmp test
	cd derecho && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --nthreads 32 --steps-per-node 2 ./hw_cmdfile # openmp test
	cd derecho && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 -q casper@casper-pbs --ppn 32 --nthreads 4 -N derecho2casper_openmp_test ./omp_cmdfile # openmp test, derecho cross submission
	cd derecho && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --processors-per-node 128 --nthreads 8 --steps-per-node 16 --memory 100G --queue preempt --cpu_type milan --random_start_delay 5 -N all_args_test ./omp_cmdfile # all args

check_casper: gs_openmp omp_cmdfile hw_cmdfile
	$(call setup_suite_dir,casper)
	cd casper && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 # check defaults
	cd casper && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 ./smalltest # njobs < ppn
	cd casper && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --nthreads 4 --steps-per-node 8 ./omp_cmdfile # openmp test
	cd casper && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 -q main@desched1 --nthreads 4 -N casper2derecho_openmp_test ./omp_cmdfile # openmp test, derecho cross submission
#	cd casper && echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --processors-per-node 32 --nthreads 8 --steps-per-node 4 --memory 300G --queue casper --cpu_type cascadelake --random_start_delay 5 -N all_args_test ./omp_cmdfile # all args

check: check_$(NCAR_HOST)

# remove everything the check_derecho / check_casper jobs wrote.
clean_derecho clean_casper:
	rm -rf ./$(subst clean_,,$@)
