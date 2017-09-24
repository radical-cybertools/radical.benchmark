#!/bin/bash

# ------------------------------------------------------------------------------
# workload and environment setup

# module load python
# module load python_setuptools
# module load python_virtualenv

export OMPI=/home/merzky/radical/ompi/installed/2017_09_18_539f71d
export PATH=$OMPI/bin/:$PATH
export LD_LIBRARY_PATH=$OMPI/lib/:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=$OMPI/share/pkgconfig/:$PKG_CONFIG_PATH
export PWD=`pwd -P`


# ensure cleanup on all exit modes
\trap cleanup_handler QUIT
\trap cleanup_handler EXIT
\trap cleanup_handler TERM

# ------------------------------------------------------------------------------
cleanup_handler() {
    # make sure we kill any DVM we have running right now
    if ! test -z "$DVM_PID"
    then
        echo "kill dvm at $DVM_PID"
        kill "$DVM_PID"
        DVM_PID=
    fi
}

count_running() {
    # count active orterun processes (== number of active tasks)
    ps -ef                       \
        | grep orterun           \
        | grep -v -e grep -e vim \
        | wc -l
}


# ------------------------------------------------------------------------------
# for all entries in the given table, run the respective experiment.  We expect
# one experiment per line, with the structure as identified by the `read`
# command below.
main(){

    TABLE="$1"
    workload="$PWD/09_mpi_units.sh"
    workload="/bin/true"

    while read -r ID RUN_NUM TASK_NUM TASK_SIZE GEN_NUM PILOT_NUM PILOT_SIZE TTC WALLTIME
    do
        if test "$ID" == '#'
        then
            continue
        fi
        benchmark_run "$ID" "$PILOT_SIZE" "$TASK_NUM" "$TASK_SIZE" "$WORKLOAD"
    done < "$TABLE"
}


# ------------------------------------------------------------------------------
#
benchmark_run(){

    # run a given benchmark experiment
    #
    # Arguments:
    #   $1: iteration number
    #   $2: pilot size
    #   $3: number of tasks
    #   $4: size of tasks (number of processes)
    #   $5: workload
    #
    # We expect '$1.$2.$3.$4" to be a unique string
    
    ITERATION=$1
    PILOT_SIZE=$2
    TASK_NUM=$3
    TASK_SIZE=$4
    WORKLOAD=$5

    echo "$ID - $PILOT_SIZE - $TASK_NUM - $TASK_SIZE"

    BUID="log.$ITERATION.$PILOT_SIZE.$TASK_NUM.$TASK_SIZE"
    LOGD="$PWD/$BUID"

    echo mkdir $LOGD
    if test -d "$LOGD"
    then
        echo "this experiment has been run before"
        return
    fi
    mkdir -p "$LOGD"
    
    GEN_SIZE=$((PILOT_SIZE/TASK_SIZE))
    GEN_NUM=$((TASK_NUM/GEN_SIZE))
    
    echo
    echo "TASK_NUM  : $TASK_NUM"
    echo "TASK_SIZE : $TASK_SIZE"
    echo "PILOT_SIZE: $PILOT_SIZE"
    echo "GEN_SIZE  : $GEN_SIZE"
    echo "GEN_NUM   : $GEN_NUM"
    echo
    
    # how many tasks fit into one generation:
    if test "$TASK_NUM" -lt "$GEN_SIZE"
    then
        GEN_SIZE=$TASK_NUM
        echo "limit to one partial generation [$GEN_SIZE]"
    fi
    
    
  # HOSTLIST="localhost"
  # HOST_IDX=1
  # while test "$HOST_IDX" -lt "$PILOT_SIZE"
  # do
  #     HOSTLIST="$HOSTLIST,localhost"
  #     HOST_IDX=$((HOST_IDX+1))
  # done
  # echo "hostlist: $HOSTLIST"
  # HOSTARG="-H $HOSTLIST
    
    # --------------------------------------------------------------------------
    # dvm setup
    echo -n 'start orte-dvm '
    ( (/usr/bin/stdbuf -oL orte-dvm -d 10 "$HOSTARG" >"$LOGD/dvm.log" 2>&1 & ) & )
    DVM_PID=$(ps -ef | grep orte-dvm | grep -v grep | xargs echo | cut -f 2 -d ' ')
    
    CNT=0
    URI=''
    while test "$CNT" -lt 100
    do
        CNT=$((CNT+1))
        URI=$(grep VMURI $LOGD/dvm.log | cut -f 2- -d ':' | xargs echo)
        if test -z "$URI"
        then
            echo -n '.'
            /bin/sleep 0.01
        else
            break
       fi
    done
    
    if test -z "$URI"
    then
        echo 'failed'
        exit -1
    fi
    echo " $URI"
    
    
    # --------------------------------------------------------------------------
    # prepare task creation
    ORTERUN="$OMPI/bin/orterun --bind-to none --oversubscribe -np $TASK_SIZE"
    
    # --------------------------------------------------------------------------
    # start first generation
    TASKS_RUNNING=0
    TASK_ID=0
    GEN_ID=0
    
    echo -n "start gen $GEN_ID : "
    while test "$TASK_ID" -lt "$GEN_SIZE"
    do
        $ORTERUN --hnp "$URI" "/bin/sh" "$WORKLOAD" > "$LOGD/$TASK_ID.log" 2>&1 &
        TASK_ID=$((TASK_ID+1))
        TASKS_RUNNING=$((TASKS_RUNNING+1))
        echo -n ".$TASK_ID"
    done
    echo
    GEN_ID=$((GEN_ID+1))
    
    
    # --------------------------------------------------------------------------
    # all other generations need to first find a task finished before starting
    # the next one.  This does not increase TASKS_RUNNING.
    
    while test "$GEN_ID" -lt "$GEN_NUM"
    do
        echo -n "start gen $GEN_ID : "
        GEN_ID=$((GEN_ID+1))
        while test "$TASK_ID" -lt $((GEN_ID * GEN_SIZE))
        do
            # wait for space
            n_running=$(count_running)
            while ! test "$n_running" -lt "$GEN_SIZE"
            do
              # echo -n "w$n_running:$pid_running "
                /bin/sleep 0.01
                n_running=$(count_running)
            done
    
            $ORTERUN --hnp "$URI" "/bin/sh" "$LOGD/09_mpi_units.sh" > "$LOGD/$TASK_ID.log" 2>&1 &
            TASK_ID=$((TASK_ID+1))
            echo -n ".$TASK_ID"
        done
        echo
    done
    
    # --------------------------------------------------------------------------
    # all tasks are started -wait for the last gen to finish
    echo -n "wait  gen $GEN_ID : "
    n_running=$(count_running)
    while ! test "$n_running" -lt "$GEN_SIZE"
    do
      # echo -n "w$n_running:$pid_running "
        /bin/sleep 0.01
        n_running=$(count_running)
    done
    
    echo
    echo 'all done'
}


# ------------------------------------------------------------------------------
#
main "$1"
#
# ------------------------------------------------------------------------------

