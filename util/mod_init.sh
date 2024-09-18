# First source the modules init
. /glade/u/apps/$NCAR_HOST/default/util/localinit.sh

# Now remove this hack
unset BASH_ENV

# Update modules to clean up path redundencies
# Can't actually use "module update" as that will change versions on you (to defaults)
PBS_O_MODULES=$(module -t list |& xargs)
module -q purge
module -q load $PBS_O_MODULES
