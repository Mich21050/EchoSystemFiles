#!/bin/sh

#
# zram.sh
#
# Copyright (c) 2012 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# PROPRIETARY/CONFIDENTIAL
#
# Use is subject to license terms.
#

#
# Set up zram disksize and enable swap on zram.
#
ZRAM_DISKSIZE="104857600"

echo 1 > /sys/block/zram0/reset
echo $ZRAM_DISKSIZE > /sys/block/zram0/disksize

# Write 1 page at a time to swap. And set aggresive swap.
echo 0 > /proc/sys/vm/page-cluster
echo 100 > /proc/sys/vm/swappiness

mkswap /dev/zram0
swapon -a /dev/zram0

exit 0
