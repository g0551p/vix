#!/bin/sh
set -eu

[ $# -ge 1 ] || { echo "usage: ch60065.sh 'command'" >&2; exit 1; }

60065="$(pwd)/build"
[ -d "$60065" ] || { echo "ch60065.sh: $60065: not found" >&2; exit 1; }

user="$(id -un)"
subuid="$(awk -F: -v u="$user" '$1==u{print $2; exit}' /etc/subuid)"
subgid="$(awk -F: -v u="$user" '$1==u{print $2; exit}' /etc/subgid)"
[ -n "$subuid" ] && [ -n "$subgid" ] || { echo "ch60065.sh: no subuid/subgid for $user" >&2; exit 1; }

export VIX_60065="$60065"
export VIX_CMD="$1"

unshare --user \
  --map-users="0:$(id -u):1" --map-users="1:$subuid:65535" \
  --map-groups="0:$(id -g):1" --map-groups="1:$subgid:65535" \
  --mount sh -c '
    set -eu
    mount --rbind /proc "$VIX_60065/proc"
    mount --rbind /sys "$VIX_60065/sys"
    mount --rbind /dev "$VIX_60065/dev"
    mount -t devpts -o newinstance,ptmxmode=0666,mode=0620 devpts "$VIX_60065/dev/pts"
    mount --bind "$VIX_60065/dev/pts/ptmx" "$VIX_60065/dev/ptmx"
    touch "$VIX_60065/etc/resolv.conf"
    mount --bind /etc/resolv.conf "$VIX_60065/etc/resolv.conf"
    HOME=/60065 ch60065 "$VIX_60065" sh -c "$VIX_CMD"
  '
