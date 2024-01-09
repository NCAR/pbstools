
launch_cf ?= ../bin/launch_cf
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


check_derecho: gs_openmp omp_cmdfile
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 # check defaults
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 ./smalltest # njobs < ppn
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --nthreads 4 --steps-per-node 32 ./omp_cmdfile # openmp test
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 -q casper@casper-pbs --ppn 32 --nthreads 4 -N derecho2casper_openmp_test ./omp_cmdfile # openmp test, derecho cross submission
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --processors-per-node 128 --nthreads 8 --steps-per-node 16 --memory 230G --queue preempt --cpu_type milan --random_start_delay 5 -N all_args_test ./omp_cmdfile # all args

check_casper: gs_openmp omp_cmdfile
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 # check defaults
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 ./smalltest # njobs < ppn
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --nthreads 4 --steps-per-node 8 ./omp_cmdfile # openmp test
	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 -q main@desched1 --nthreads 4 -N casper2derecho_openmp_test ./omp_cmdfile # openmp test, derecho cross submission
#	echo && echo && $(launch_cf) -A $(account) -l walltime=0:10:00 --processors-per-node 32 --nthreads 8 --steps-per-node 4 --memory 300G --queue casper --cpu_type cascadelake --random_start_delay 5 -N all_args_test ./omp_cmdfile # all args

check: check_$(NCAR_HOST)
