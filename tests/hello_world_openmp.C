#include <iostream>
#include <iomanip>
#include <omp.h>
#include <unistd.h>



int main (int argc, char **argv)
{
  int nthreads=1;
  char hn[256];

  gethostname(hn, sizeof(hn) / sizeof(char));

#pragma omp parallel
  { if (0 == omp_get_thread_num()) nthreads = omp_get_num_threads(); }

  std::cout << "Hello from " << std::string (hn)
            << " running with " << nthreads << " threads"
            << std::endl;

  return 0;
}
