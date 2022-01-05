#!/bin/sh

. $D/etc/default/rcS

clearcache=0
exec 9</proc/cmdline
while read line <&9
do
        case "$line" in
                *clearcache*)  clearcache=1
                               ;;
                *)             continue
                               ;;
        esac
done
exec 9>&-

if test -e /etc/volatile.cache -a "$VOLATILE_ENABLE_CACHE" = "yes" -a "x$1" != "xupdate" -a "x$clearcache" = "x0"
then
       sh /etc/volatile.cache
fi

if test -f /etc/ld.so.cache -a ! -f /var/run/ld.so.cache
then
       ln -s /etc/ld.so.cache /var/run/ld.so.cache
fi

