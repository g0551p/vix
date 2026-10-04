#!/bin/sh
set -eu

root="${1:-build}"
out="${2:-vix.iso}"

nixpath() { nix build --no-link "$1" >/dev/null 2>&1; nix eval --raw "$1"; }

BB="$(nix build --impure --no-link --print-out-paths --expr 'with import <nixpkgs> {}; pkgsStatic.busybox')"
KMOD="$(nixpath nixpkgs#kmod)"
SQUASH="$(nixpath nixpkgs#squashfsTools)"
XZ="$(nixpath nixpkgs#xz)"
GZIP="$(nixpath nixpkgs#gzip)"
CPIO="$(nixpath nixpkgs#cpio)"
LINUX="$(nixpath nixpkgs#linux)"
MODULES="$(nixpath nixpkgs#linux.modules)"
GBIOS="$(nixpath nixpkgs#grub2)"
GEFI="$(nixpath nixpkgs#grub2_efi)"
DOSFS="$(nixpath nixpkgs#dosfstools)"
MTOOLS="$(nixpath nixpkgs#mtools)"
XORRISO="$(nixpath nixpkgs#xorriso)"
SQLITE="$(nixpath nixpkgs#sqlite)"

kver="$(ls "$MODULES/lib/modules")"

chmod -R u+w .iso .initrd 2>/dev/null || true
rm -rf .iso .initrd
mkdir -p .iso/boot/grub .iso/LiveOS .iso/EFI .initrd/bin

echo ">> kernel modules into rootfs"
mkdir -p "$root/usr/lib/modules"
[ -e "$root/usr/lib/modules/$kver" ] || cp -r "$MODULES/lib/modules/$kver" "$root/usr/lib/modules/"
chmod -R u+w "$root/usr/lib/modules/$kver"
"$KMOD/bin/depmod" -b "$root/usr" "$kver" 2>/dev/null || true

mkdir -p "$root/usr/lib/firmware"

if [ -n "${VIX_FIRMWARE:-}" ]; then
  echo ">> firmware"
  for p in linux-firmware sof-firmware alsa-firmware; do
    f="$(nixpath "nixpkgs#$p")"
    cp -a --no-preserve=mode "$f/lib/firmware/." "$root/usr/lib/firmware/" 2>/dev/null || true
  done
fi

echo ">> regulatory.db"
REGDB="$(nixpath nixpkgs#wireless-regdb)"
cp -a --no-preserve=mode "$REGDB/lib/firmware/." "$root/usr/lib/firmware/"
chmod -R u+w "$root/usr/lib/firmware"

if [ -e "$root/nix/var/nix/db/db.sqlite" ]; then
  echo ">> checkpoint nix db"
  "$SQLITE/bin/sqlite3" "$root/nix/var/nix/db/db.sqlite" \
    'PRAGMA wal_checkpoint(TRUNCATE);' >/dev/null 2>&1 || true
  rm -f "$root/nix/var/nix/db/db.sqlite-wal" "$root/nix/var/nix/db/db.sqlite-shm"
fi

echo ">> kernel $kver"
cp "$LINUX/bzImage" .iso/boot/vmlinuz

echo ">> initramfs"
cp "$BB/bin/busybox" .initrd/bin/busybox
chmod 755 .initrd/bin/busybox

mods="overlay squashfs loop isofs udf sr_mod cdrom \
      ahci ata_piix libata sd_mod nvme \
      virtio virtio_pci virtio_blk virtio_scsi \
      usb_storage uas xhci_hcd xhci_pci ehci_hcd ehci_pci ohci_hcd uhci_hcd \
      usbhid hid hid_generic atkbd i8042 psmouse evdev \
      ext4 btrfs xfs vfat \
      ${VIX_EXTRA_MODS:-}"
for m in $mods; do
  "$KMOD/bin/modprobe" -d "$MODULES" -S "$kver" --show-depends "$m" 2>/dev/null | awk '{print $2}'
done | sort -u | while read -r ko; do
  [ -f "$ko" ] || continue
  rel="${ko#"$MODULES"/}"
  dest=".initrd/$rel"
  mkdir -p "$(dirname "$dest")"
  case "$ko" in
    *.xz) "$XZ/bin/xz" -dc "$ko" >"${dest%.xz}" ;;
    *.gz) "$GZIP/bin/gzip" -dc "$ko" >"${dest%.gz}" ;;
    *) cp "$ko" "$dest" ;;
  esac
done
"$KMOD/bin/depmod" -b .initrd "$kver" 2>/dev/null || true

cp boot/init .initrd/init
chmod 755 .initrd/init
( cd .initrd && find . -print | "$CPIO/bin/cpio" -o --format=newc --quiet ) \
  | "$GZIP/bin/gzip" -9 >.iso/boot/initrd.img

echo ">> kernel + initrd into rootfs"
mkdir -p "$root/usr/lib/vix"
cp .iso/boot/vmlinuz "$root/usr/lib/vix/vmlinuz"
cp .iso/boot/initrd.img "$root/usr/lib/vix/initrd.img"

echo ">> rootfs.squashfs"
"$SQUASH/bin/mksquashfs" "$root" .iso/LiveOS/rootfs.squashfs \
  -comp zstd -noappend -all-root -quiet

echo ">> grub"
cp boot/grub.cfg .iso/boot/grub/grub.cfg
cp -r "$GBIOS/lib/grub/i386-pc" .iso/boot/grub/i386-pc
chmod -R u+w .iso/boot/grub/i386-pc

printf '%s\n' \
  'search --no-floppy --label VIX --set=root' \
  'set prefix=($root)/boot/grub' \
  'configfile ($root)/boot/grub/grub.cfg' >.initrd/boot.cfg

"$GBIOS/bin/grub-mkimage" -O i386-pc-eltorito \
  -d "$GBIOS/lib/grub/i386-pc" -p '(cd)/boot/grub' \
  -o .iso/boot/grub/i386-pc/eltorito.img \
  biosdisk iso9660 part_gpt part_msdos normal linux search search_label configfile echo all_video

"$GEFI/bin/grub-mkstandalone" -O x86_64-efi -o .iso/EFI/BOOTX64.EFI \
  --modules="iso9660 part_gpt part_msdos fat normal linux search search_label configfile echo all_video" \
  --fonts= --themes= --locales= \
  "boot/grub/grub.cfg=.initrd/boot.cfg"

echo ">> efiboot.img"
dd if=/dev/zero of=.iso/EFI/efiboot.img bs=1M count=8 status=none
"$DOSFS/bin/mkfs.vfat" .iso/EFI/efiboot.img >/dev/null
"$MTOOLS/bin/mmd" -i .iso/EFI/efiboot.img ::/EFI ::/EFI/BOOT
"$MTOOLS/bin/mcopy" -i .iso/EFI/efiboot.img .iso/EFI/BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI
rm -f .iso/EFI/BOOTX64.EFI

echo ">> iso"
rm -f "$out"
"$XORRISO/bin/xorriso" -as mkisofs \
  -iso-level 3 -full-iso9660-filenames -volid VIX \
  -eltorito-boot boot/grub/i386-pc/eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
  -eltorito-alt-boot -e EFI/efiboot.img -no-emul-boot \
  -isohybrid-gpt-basdat \
  -o "$out" .iso

ls -lh "$out"
