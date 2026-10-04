#!/bin/sh
set -eu

[ $# -ge 1 ] || { echo "usage: chroot.sh 'command'" >&2; exit 1; }

root="$(pwd)/build"
[ -d "$root" ] || { echo "chroot.sh: $root: not found" >&2; exit 1; }

user="$(id -un)"
subuid="$(awk -F: -v u="$user" '$1==u{print $2; exit}' /etc/subuid)"
subgid="$(awk -F: -v u="$user" '$1==u{print $2; exit}' /etc/subgid)"
[ -n "$subuid" ] && [ -n "$subgid" ] || { echo "chroot.sh: no subuid/subgid for $user" >&2; exit 1; }

export VIX_ROOT="$root"
export VIX_CMD="$1"

unshare --user \
  --map-users="0:$(id -u):1" --map-users="1:$subuid:65535" \
  --map-groups="0:$(id -g):1" --map-groups="1:$subgid:65535" \
  --mount sh -c '
    set -eu
    mount --rbind /proc "$VIX_ROOT/proc"
    mount --rbind /sys "$VIX_ROOT/sys"
    mount --rbind /dev "$VIX_ROOT/dev"
    mount -t devpts -o newinstance,ptmxmode=0666,mode=0620 devpts "$VIX_ROOT/dev/pts"
    mount --bind "$VIX_ROOT/dev/pts/ptmx" "$VIX_ROOT/dev/ptmx"
    touch "$VIX_ROOT/etc/resolv.conf"
    mount --bind /etc/resolv.conf "$VIX_ROOT/etc/resolv.conf"
    HOME=/root chroot "$VIX_ROOT" sh -c "$VIX_CMD"
  '
