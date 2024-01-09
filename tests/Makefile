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
	for i in $$(seq 1 512); do \
	  echo "./gs_openmp $$((1024*8*2)) # step $${i}" >> $@.tmp ; \
	done
	mv $@.tmp $@


check: gs_openmp omp_cmdfile
	$(launch_cf) -A $(account) -l walltime=0:10:00 # check defaults
	sleep 3
	$(launch_cf) -A $(account) -l walltime=0:10:00 ./smalltest # njobs < ppn
	sleep 3
	$(launch_cf) -A $(account) -l walltime=0:10:00 --nthreads 4 --steps-per-node 32 ./omp_cmdfile # openmp test
	sleep 3
	$(launch_cf) -A $(account) -l walltime=0:10:00 --processors-per-node 128 --nthreads 8 --steps-per-node 16 --memory 100G --queue preempt --cpu_type milan --random_start_delay 10 -N all_args_test ./omp_cmdfile # all args
