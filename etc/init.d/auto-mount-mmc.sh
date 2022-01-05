#!/bin/sh

MOUNT=/bin/mount
BOARDQUERY=`/usr/local/bin/boardquery flash`
ECHO=/bin/echo
MMC_PARTLABEL_NAND="/dev/mmcblk0p1"
MMC_PARTLABEL_EMMC="/dev/disk/by-label/boot"
MMC_PARTLABEL_EMMC_AMP="/dev/disk/by-label/Amped"
MMC_MOUNT_POINT="/media/card"

die() {
    $ECHO "Fatal error: $@" &>2
    exit 1
}

case ${BOARDQUERY} in
    "NAND")
        if [ -b "$MMC_PARTLABEL_NAND" ]
        then
            MMC_PART=$MMC_PARTLABEL_NAND
        else
            $ECHO "MMC not detected"
            exit 0
        fi
    ;;
    "eMMC")
        if [ -b "$MMC_PARTLABEL_EMMC" ]
        then
            MMC_PART=$MMC_PARTLABEL_EMMC
        elif [ -b "$MMC_PARTLABEL_EMMC_AMP" ]
        then
            MMC_PART=$MMC_PARTLABEL_EMMC_AMP
        else
            $ECHO "MMC not detected"
            exit 0
        fi
    ;;
    *)
       $ECHO "Unrecognized board type"
       exit 0
    ;;
esac

if [ -d "$MMC_MOUNT_POINT" ]
then
    $MOUNT -t auto $MMC_PART $MMC_MOUNT_POINT || die "Failed to mount"
else
    die "Mount Directory $MMC_MOUNT_POINT does not exist"
fi

exit 0
