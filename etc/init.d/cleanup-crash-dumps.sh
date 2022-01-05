#!/bin/bash

LOGDIR="/var/local/log"
RAWCORESPATTERN="Core-*.bin"
ZIPCORESPATTERN="Core-*.bin.gz"
ALLCORESPATTERN="Core-*.bin*"
WIPPREFIX="WIP-"
WIPCOREPATTERN="${WIPPREFIX}${RAWCORESPATTERN}"

LOGERR() { logger -p local4.err -t "system: E cleanup-crash-dumps:" $@; }
LOGINFO() { logger -p local4.info -t "system: I cleanup-crash-dumps:" $@; }

process_wip_core() {
    WIPFILE=$1

    if [ -f $WIPFILE ]
    then
        # crash-monitor is invoked like so by the kernel.
        # see man core(5) for fields
        # |/usr/local/bin/crash-monitor %e %p %s %u %g %t 27

        # Lets get those same fields out.
        # explode the file name with "-" as the separator.
        IFS='-' read -ra FILEPARTS <<< "${WIPFILE}"

        # WIP Core alarmd 1556 7 1387392814 B0F00103310600U5.bin
        e=$(which ${FILEPARTS[2]})
        p=${FILEPARTS[3]}
        s=${FILEPARTS[4]}
        u=0
        g=0
        t=${FILEPARTS[5]}

        # Pretend to be the kernel and send this core dump to crash monitor.
        # The normal last arg is 27
        # 27 = 0x1B = 0b11011 == 0x10 | 0x08 | 0x02 | 0x01
        # which means: MonitorLogCoreInfo | MonitorUploadCoreDump | MonitorUploadMetric | MonitorOnDevelopmentBuild
        # We dont want to log the metric (again), so no MonitorUploadMetric
        # So our flags are: MonitorLogCoreInfo | MonitorUploadCoreDump | MonitorOnDevelopmentBuild
        # Which is 0x10 | 0x08 | 0x01 = 0x19 = 25
        cat $WIPFILE | /usr/local/bin/crash-monitor $e $p $s $u $g $t 25

        # We can delete the WIP file now, since crashmonitor should save it to a non-WIP version.
        rm -f $WIPFILE
    else
        LOGERR "Unable to process non-existent WIP core file $WIPFILE"
    fi
}

# Take a raw core, rename to a WIP core and process the WIP core.
process_core() {
    CORE_FILE=$1
    mv ${CORE_FILE} ${WIPPREFIX}${CORE_FILE}
    LOGINFO "Sending ${WIPPREFIX}${CORE_FILE} to crash-monitor"
    process_wip_core ${WIPPREFIX}${CORE_FILE}
}

# Take a zipped core, unzip it to a WIP file and delete the original.
# Process the WIP core.
process_zipped_core() {
    ZIPPED_CORE=$1
    UNZIPPED_CORE=${WIPPREFIX}${ZIPPED_CORE}.raw
    LOGINFO "Unzipping $ZIPPED_CORE to $UNZIPPED_CORE"
    gunzip -c $ZIPPED_CORE > $UNZIPPED_CORE
    rm -f $ZIPPED_CORE
    LOGINFO "Sending $UNZIPPED_CORE to crash-monitor"
    process_wip_core $UNZIPPED_CORE
}

# When we have both the raw core dump and the gzipped core dump, we delete the gzipped one,
# so that we can send the raw one along to crash-monitor
dedupe_core_files() {
    RAWCORES=($RAWCORESPATTERN)
    for core in ${RAWCORES[@]}
    do
        zipcore="${core}.gz"
        # Blindly delete. It's ok if it doesnt exist.
        rm -f $zipcore
    done
}

prune_till_percent() {
    PERCENT=$1
    FULLNESS=$(df -P ${LOGDIR} | tail -1 | awk '{print $5}' | sed 's/\%//g')
    until [ ${FULLNESS} -lt ${PERCENT} ]
    do
        OLDESTCORE=$(ls -1rt ${LOGDIR}/${ALLCORESPATTERN} | head -1)

        if [ "x${OLDESTCORE}" == "x" ]
        then
            # If we have no cores, and the disk is full, this script is not very useful :\
            exit 1
        fi
        rm -f $OLDESTCORE

        FULLNESS=$(df -p ${LOGDIR} | tail -1 | awk '{print $5}' | sed 's/\%//g')
    done
}

#-- Starts Here ----------------

# We want globs to return empty
shopt -s nullglob
pushd ${LOGDIR}

# Cores can accumulate in 2 ways
# 1. Coredump happened on shutdown, and the raw core is sitting around, since GDB never finished.
#    In this case, we can have duplicated zipped cores and raw cores.
# 2. The gzipped core dump is here, because TMD/loguploadd never finished, and we rebooted.

# Step 0: Get rid of redundant files.
dedupe_core_files

# Step 1, get /var/local to atleast 80% full
prune_till_percent 80

# Step 2. Upload any previously interrupted work in progress core.
WIPCORES=($WIPCOREPATTERN)
for wipcore in ${WIPCORES[@]}
do
    LOGINFO "Processing old WIP core file: $wipcore"
    process_wip_core $wipcore
done

# Step 3. Upload all raw cores. (Free up disk faster?)
RAWCORES=($RAWCORESPATTERN)
for rawcore in ${RAWCORES[@]}
do
    LOGINFO "Processing old RAW core file: $rawcore"
    process_core $rawcore
done

# Step 4. Unzip and Upload all zipped cores.
ZIPCORES=($ZIPCORESPATTERN)
for zipcore in ${ZIPCORES[@]}
do
    LOGINFO "Processing old gzipped core file: $zipcore"
    process_zipped_core $zipcore
done

popd
