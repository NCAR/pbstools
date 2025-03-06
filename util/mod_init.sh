# Let's ensure we cannot repeat this...
if [[ -z $__PBS_MOD_INIT_HACK ]]; then
    export __PBS_MOD_INIT_HACK=1

    # First source the modules init
    if [[ -n $NCAR_HOST ]]; then
        . /glade/u/apps/$NCAR_HOST/default/util/localinit.sh
    elif [[ $(hostname) == de* ]]; then
        . /glade/u/apps/derecho/default/util/localinit.sh
    else
        . /glade/u/apps/casper/default/util/localinit.sh
    fi

    # Now remove this hack
    unset BASH_ENV

    # Update modules to clean up path redundencies
    # Can't actually use "module update" as that will change versions on you (to defaults)
    PBS_O_MODULES=$(module -t list |& xargs)
    module -q purge
    module -q load $PBS_O_MODULES
fi
