#!/bin/sh
. $D/etc/default/rcS

CFGDIR="$D/etc/default/volatiles"
TMPROOT="$D/var/tmp"
COREDEF="00_core"

[ "${VERBOSE}" != "no" ] && echo "Populating volatile Filesystems."

create_file() {
EXEC="
touch \"$1\";
chown ${TUSER}.${TGROUP} $1 || echo \"Failed to set owner -${TUSER}- for -$1-.\" >/dev/tty0 2>&1;
chmod ${TMODE} $1 || echo \"Failed to set mode -${TMODE}- for -$1-.\" >/dev/tty0 2>&1 "

test "$VOLATILE_ENABLE_CACHE" = yes && echo "$EXEC" >> $D/etc/volatile.cache.build

[ -e "$D$1" ] && {
  [ "${VERBOSE}" != "no" ] && echo "Target already exists. Skipping."
}
}

mk_dir() {
EXEC="
mkdir -p \"$1\";
chown ${TUSER}.${TGROUP} $1 || echo \"Failed to set owner -${TUSER}- for -$1-.\" >/dev/tty0 2>&1;
chmod ${TMODE} $1 || echo \"Failed to set mode -${TMODE}- for -$1-.\" >/dev/tty0 2>&1 "

test "$VOLATILE_ENABLE_CACHE" = yes && echo "$EXEC" >> $D/etc/volatile.cache.build

[ -e "$D$1" ] && {
  [ "${VERBOSE}" != "no" ] && echo "Target already exists. Skipping."
}
}

link_file() {
if  test -e \"$D$2\" -o -L $D$2
then
    return 0
fi

EXEC="test -e \"$2\" -o -L $2 || ln -s \"$1\" \"$2\" >/dev/tty0 2>&1"

test "$VOLATILE_ENABLE_CACHE" = yes && echo "	$EXEC" >> $D/etc/volatile.cache.build

[ -e "$D$2" ] && {
  echo "Cannot create link over existing -${TNAME}-." >&2
}
}

check_requirements() {

cleanup() {
 rm "${TMP_INTERMED}"
 rm "${TMP_DEFINED}"
 rm "${TMP_COMBINED}"
}

CFGFILE="$1"

[ `basename "${CFGFILE}"` = "${COREDEF}" ] && return 0

TMP_INTERMED="${TMPROOT}/tmp.$$"
TMP_DEFINED="${TMPROOT}/tmpdefined.$$"
TMP_COMBINED="${TMPROOT}/tmpcombined.$$"


cat $D/etc/passwd | sed 's@\(^:\)*:.*@\1@' | sort | uniq > "${TMP_DEFINED}"
cat ${CFGFILE} | grep -v "^#" | cut -d " " -f 2 > "${TMP_INTERMED}"
cat "${TMP_DEFINED}" "${TMP_INTERMED}" | sort | uniq > "${TMP_COMBINED}"

NR_DEFINED_USERS="`cat "${TMP_DEFINED}" | wc -l`"
NR_COMBINED_USERS="`cat "${TMP_COMBINED}" | wc -l`"

[ "${NR_DEFINED_USERS}" -ne "${NR_COMBINED_USERS}" ] && {
  echo "Undefined users:"
  diff "${TMP_DEFINED}" "${TMP_COMBINED}" | grep "^>"
  cleanup
  return 1
}

cat $D/etc/group | sed 's@\(^:\)*:.*@\1@' | sort | uniq > "${TMP_DEFINED}"
cat ${CFGFILE} | grep -v "^#" | cut -d " " -f 3 > "${TMP_INTERMED}"
cat "${TMP_DEFINED}" "${TMP_INTERMED}" | sort | uniq > "${TMP_COMBINED}"

NR_DEFINED_GROUPS="`cat "${TMP_DEFINED}" | wc -l`"
NR_COMBINED_GROUPS="`cat "${TMP_COMBINED}" | wc -l`"

[ "${NR_DEFINED_GROUPS}" -ne "${NR_COMBINED_GROUPS}" ] && {
  echo "Undefined groups:"
  diff "${TMP_DEFINED}" "${TMP_COMBINED}" | grep "^>"
  cleanup
  return 1
  }

# Add checks for required directories here

cleanup
return 0
}

apply_cfgfile() {
CFGFILE="$1"

check_requirements "${CFGFILE}" || {
  echo "Skipping ${CFGFILE}"
  return 1
  }

cat ${CFGFILE} | grep -v "^#" | \
while read LINE; do

eval `echo "$LINE" | sed -n "s/\(.*\)\ \(.*\) \(.*\)\ \(.*\)\ \(.*\)\ \(.*\)/TTYPE=\1 ; TUSER=\2; TGROUP=\3; TMODE=\4; TNAME=\5 TLTARGET=\6/p"`

[ "${VERBOSE}" != "no" ] && echo "Checking for -${TNAME}-."


[ "${TTYPE}" = "l" ] && {
TSOURCE="$TLTARGET"
[ -L "${TNAME}" ] || {
[ "${VERBOSE}" != "no" ] && echo "Creating link -${TNAME}- pointing to -${TSOURCE}-."
link_file "${TSOURCE}" "${TNAME}" &
}
continue
}

[ -L "${TNAME}" ] && {
[ "${VERBOSE}" != "no" ] && echo "Found link."
NEWNAME=`ls -l "${TNAME}" | sed -e 's/^.*-> \(.*\)$/\1/'`
echo ${NEWNAME} | grep -v "^/" >/dev/null && {
TNAME="`echo ${TNAME} | sed -e 's@\(.*\)/.*@\1@'`/${NEWNAME}"
[ "${VERBOSE}" != "no" ] && echo "Converted relative linktarget to absolute path -${TNAME}-."
} || {
TNAME="${NEWNAME}"
[ "${VERBOSE}" != "no" ] && echo "Using absolute link target -${TNAME}-."
 }
}

case "${TTYPE}" in
  "f")  [ "${VERBOSE}" != "no" ] && echo "Creating file -${TNAME}-."
        create_file "${TNAME}" &
        ;;
  "d")  [ "${VERBOSE}" != "no" ] && echo "Creating directory -${TNAME}-."
        mk_dir "${TNAME}" &
        # Add check to see if there's an entry in fstab to mount.
        ;;
  *)    [ "${VERBOSE}" != "no" ] && echo "Invalid type -${TTYPE}-."
        continue
        ;;
esac

done

return 0

  }

rm -f $D/etc/volatile.cache $D/etc/volatile.cache.build
for file in `ls -1 "${CFGDIR}" | sort`; do
	apply_cfgfile "${CFGDIR}/${file}"
done

[ -e $D/etc/volatile.cache.build ] && mv $D/etc/volatile.cache.build $D/etc/volatile.cache


