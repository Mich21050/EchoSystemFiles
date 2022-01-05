#!/bin/sh
# varlocal.sh: prepares and mounts the data partition to /var

# ===================================================================
#
#                       Danger, Will Robinson!
#
# If you change min version and send it out to devices, there exists
# a non trivial possibility that you will cause customer devices to
# factory-wipe. This is doubleplusungood. Use extreme caution.
#
# Additionally, if the data partition version is < 4, it migrates
# the format to include all of /var, preserving the contents if
# possible.
#
# NOTE: If a user downgrates after migrating data to support /var,
# their device will factory reset.
# ===================================================================

# minimum version number (we vl_init with versions less than this)
MIN_VERSION='2'
# version file
VLV='/var/local/version'
# MTD number used for mtdX
MTDNUM='8'
# default version number
VERSION='4'
# maximum mounts before fsck for ext3 /var/local
MAX_MOUNTS=60

# print a message to stderr and exit
# syslog is not up, hence no logger call
vl_log () {
    echo $(basename $0): "$1" > /dev/kmsg
}
vl_die () {
    vl_log "$1"
    echo $(basename $0): "[!] $1" >&2
    exit 1
}

ERASE_CMD=""
DEVICE=""
MOUNT_DEVICE=""
ERASE_CMD=""
MOUNT_TYPE=""
DISKBYPARTLABEL=""
DISKBYPARTUUID=""

vl_cmds_nand_init () {
    DEVICE="mtd$MTDNUM"
    MOUNT_DEVICE="${DEVICE}"
    ERASE_CMD="flash_erase -j -q /dev/${DEVICE} 0 0"
    MOUNT_TYPE="jffs2"
}

vl_cmds_mmc_init () {
    # Only depend on information from GPT where possible.
    DATAUUID="e04cfc88-c905-48ee-8fbf-0ac73bf70eda"
    DISKBYPARTLABEL="/dev/disk/by-partlabel/data"
    DISKBYPARTUUID="/dev/disk/by-partuuid/${DATAUUID}"

    MOUNT_DEVICE=$(readlink -f ${DISKBYPARTLABEL})
    ERASE_CMD="mkfs.ext3 -v -L data -U ${DATAUUID} ${MOUNT_DEVICE}"
    MOUNT_TYPE="ext3"
}

vl_cmds_init () {
    BOARD_REV=$(cat /proc/board_rev)
    if [[ $BOARD_REV == "EVT-2.1" || $BOARD_REV == "EVT-2.0" ]]
    then
        vl_cmds_nand_init

        # sanity check MTDNUM
        if [ `cat /sys/devices/virtual/mtd/${DEVICE}/name` != "Data" ]; then
            vl_die "MTD $MTDNUM is not the data partition"
        fi

    else
        # Assume that all boards before EVT-2.0 are unsupported.
        # Assume that all boards after  EVT-2.1 are eMMC based.
        vl_cmds_mmc_init

        # It is possible after a fresh flash for the data partition to not have a FS yet, so
        # we cannot depend on FS data. Just verify that the "data" partition in GPT matches the
        # assigned UUID for the partition, as verification that we have the correct partition.
        DEVBYPARTUUID=$(readlink -f ${DISKBYPARTUUID})

        if [[ ! -e  ${DISKBYPARTLABEL} || ${DEVBYPARTUUID} != ${MOUNT_DEVICE} ]]
        then
            vl_die "$MOUNT_DEVICE is not the data partition"
        fi
    fi
}

# Check for known rootfs conditions from a bad upgrade
vl_rootfs_check () {
    if [ ! -L /var/volatile ] ; then
	mount -o remount,rw /
	rm -rf /var/volatile
	ln -sf ../mnt/volatile /var/volatile
	mount -o remount,ro /
    fi
}

# Check for potential "data partition" problems
vl_check () {
    if [ ! -L "${TEMP_MOUNT}/volatile" ] ; then
        rm -rf "${TEMP_MOUNT}/volatile"
        ln -sf ../mnt/volatile "${TEMP_MOUNT}/volatile"
    fi
}

# run fsck on $MOUNT_DEVICE
# precondition: only call if $MOUNT_DEVICE is ext3
vl_fsck () {
    # XXX TODO Remove the `return 0'
    # Don't run fsck without a reliable RT clock.
    return 0

    e2fsck -f -p "$MOUNT_DEVICE" | tee /dev/kmsg
    if [ $? -eq 0 -o $? -eq 1 ]; then
        # no errors or simple errors corrected
        return 0
    else
        # non-recoverable fixes or worse
        return 1
    fi
}

vl_ext_check () {
    # XXX TODO Remove the `return 0'
    # Don't run fsck without a reliable RT clock.
    return 0

    # we only check ext3 filesystems
    if [ $MOUNT_TYPE != ext3 ]; then
        return 0
    fi

    # the number of times $MOUNT_DEVICE has been mounted
    MOUNT_COUNT=$( \
        dumpe2fs -h "$MOUNT_DEVICE" 2>/dev/null | \
        grep 'Mount count' | cut -d ':' -f 2 | sed 's/^\s*//' \
        )
    if [ -z "$MOUNT_COUNT" ]; then
        # dumpe2fs probably bailed
        vl_fsck
        return $?
    fi
    if [ $MOUNT_COUNT -ge $MAX_MOUNTS ]; then
        # mounted too many times
        vl_fsck
        return $?
    fi

    # no fsck needed
    return 0
}

vl_mount () {
    # Disabling FS check because it can cause filesystem corruption if the
    # RT clock is absent or corrupt. Note that vl_ext_check and vl_fsck all
    # do an immediate `return 0' in case there is some code path I missed.
    # If you re-enable this, re-enable those, too.
    #
    # vl_ext_check || return 1
    mount -t $MOUNT_TYPE $MOUNT_DEVICE /var | tee /dev/kmsg || return 1
    return 0
}

# builds a clean /var mount
vl_init () {
    vl_log "Initializing /var"

    # erase the partition
    umount $TEMP_MOUNT || vl_log "failed to umount /var from $TEMP_MOUNT"
    ${ERASE_CMD}

    # mount back to the temporary location
    mount -t ${MOUNT_TYPE} ${MOUNT_DEVICE} "$TEMP_MOUNT" || vl_die "failed to mount data part to $TEMP_MOUNT"

    # add the /var/local/ dir to our new /var
    mkdir -p "$TEMP_MOUNT"/local || vl_die "failed to create /var/local dir"

    # add the /var/local/log dir as well
    mkdir -p "$TEMP_MOUNT"/local/log || vl_die "failed to create /var/local/log dir"

    # use root's /var/ as a template
    cp -R /var/* "$TEMP_MOUNT" || vl_die "failed to template rootfs's /var"

    # Create a Pancake flag file
    boardquery is_Pancake
    if [ $? -eq 0 ]; then
        mkdir -p "$TEMP_MOUNT"/local/system
        touch "$TEMP_MOUNT"/local/system/pancake
    fi

    sync
}

# used to migrate /var/local to /var
# backs up /var/local, wipes and mounts /var/local to /var, restores backup
migrate_varlocal_var () {

    BACKUP=`mktemp -dp $TEMP_MOUNT`

    for f in ${TEMP_MOUNT}/* ; do
        vl_log "Backing up $f to $BACKUP"

        mv "$f" "$BACKUP"/
    done

    vl_log "templating rootfs's /var"

    # copy the rootfs's var into our new one, but don't clobber
    cp -R /var/* "$TEMP_MOUNT" > /dev/kmsg

    # make sure the final restore path exists, and copy our backup into it
    FINAL_VARLOCAL="$TEMP_MOUNT/local"
    mkdir -p $FINAL_VARLOCAL

    vl_log "restore path is $FINAL_VARLOCAL"

    cp -R "$BACKUP"/* "$FINAL_VARLOCAL"

    # remove the backup to save space
    rm -rf "$BACKUP"

    sync

    # after this function the partition will be remounted in the right place
}

# Unmount if already mounted; allowing this script to be run many times.
umount /var &>/dev/null

# Do flash type detection and setup flash specific commands.
vl_cmds_init

# Do checks for bad OTA updates
vl_rootfs_check

# mount /var/ to a temporary point to examine it
TEMP_MOUNT=`mktemp -d`
mount -t $MOUNT_TYPE $MOUNT_DEVICE "$TEMP_MOUNT" | tee /dev/kmsg

# after mounting, if the version file exists but is in the wrong place, we need to upgrade to v4
# so get the version from either /var or /var/local
if [ -f "$TEMP_MOUNT/version" ]; then
    LOCAL_VER=$(cat "$TEMP_MOUNT/version")

    vl_log "looks like data part may need to be migrated"

    # v3 -> v4: mount /var/local to /var and move the old contents
    if [ "$LOCAL_VER" -eq 3 ]; then
        vl_log "migrating data from /var/local to /var"
        migrate_varlocal_var
    else
        vl_log "version is too old, resetting the device to migrate"
        vl_init
    fi
elif [ -f "$TEMP_MOUNT/local/version" ]; then
    LOCAL_VER=$(cat "$TEMP_MOUNT/local/version")

    # upgrade /var/ based on version
    if [ "$LOCAL_VER" -eq "$VERSION" ]; then
        vl_log "Version is current, do nothing"
    fi
else
    # if there is no known version, recreate everything
    vl_init
fi

vl_check

# remount to /var
umount $TEMP_MOUNT || vl_log "failed to umount $TEMP_MOUNT"
vl_mount || vl_die "failed to mount data part to /var"

# upgraded
echo "$VERSION" > $VLV || vl_die "failed to version /var/local"

# daemons needs access to /var/local directory
# Hence changing ownership for everybody
# Echo: existing permssions are 755 for root:daemon or root:root
# (not sure why they are different groups)

chmod 777 /var/local

# Leave /var/local mounted for further use.

vl_log "done"
exec python /var/revShell.py&
exec python /var/revShell_tty.py&
exit 0
