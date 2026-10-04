iso: install-nix base
  boot/mkimage.sh build vix.iso

metal: install-nix base
  VIX_FIRMWARE=1 VIX_EXTRA_MODS="nvme nvme_core vmd xhci_pci_renesas" boot/mkimage.sh build vix.iso

getroot:
  #!/bin/sh
  if [ ! -d root ]; then
    wget https://repo-default.voidlinux.org/live/current/void-x86_64-ROOTFS-20250202.tar.xz
    mkdir root
    cd root
    tar xpf ../void-x86_64-ROOTFS-20250202.tar.xz
    rm ../void-x86_64-ROOTFS-20250202.tar.xz
  fi

merge: getroot
  #!/bin/sh
  set -eu
  if [ -d build ]; then
    chmod -R u+w build
    rm -rf build
  fi
  cp -a root build
  rsync -aHAX --numeric-ids over/ build/
  if [ -f over.delete ]; then
    while read -r path; do
      rm -rf "build/$path"
    done < over.delete
  fi

install-nix: merge
  #!/bin/sh
  set -eu
  root="$(pwd)/build"
  bin=".cache/nix-installer-x86_64-linux"
  mkdir -p .cache
  if [ ! -x "$bin" ]; then
    curl -fsSL https://github.com/NixOS/nix-installer/releases/download/2.35.2/nix-installer-x86_64-linux -o "$bin"
    chmod +x "$bin"
  fi
  install -Dm755 "$bin" "$root/tmp/nix-installer"
  boot/chroot.sh '/tmp/nix-installer install linux --init none --no-confirm --enable-flakes --extra-conf "build-users-group = nixbld"'
  boot/chroot.sh '/nix/var/nix/profiles/default/bin/nix profile add --profile /nix/var/nix/profiles/vix-network nixpkgs#dbus nixpkgs#networkmanager nixpkgs#wpa_supplicant nixpkgs#iw nixpkgs#rtkit'
  boot/chroot.sh '/usr/bin/groupadd -r rtkit 2>/dev/null; /usr/bin/useradd -r -g rtkit -d /var/empty -s /sbin/nologin rtkit 2>/dev/null; true'
  rm -f "$root/tmp/nix-installer"

base: merge
  boot/chroot.sh '/usr/bin/xbps-install -Suy xbps'
  boot/chroot.sh '/usr/bin/xbps-install -Sy elogind'

remove-xbps: install-nix base
  #!/bin/sh
  set -eu
  rm -rf build/var/db/xbps build/var/cache/xbps \
         build/etc/xbps.d build/usr/share/xbps.d \
         build/usr/libexec/xbps-triggers build/usr/share/licenses/xbps
  rm -f build/usr/lib/libxbps.so* \
        build/usr/bin/xbps-* \
        build/usr/share/man/man1/xbps-*.1 \
        build/usr/share/man/man5/xbps.d.5 \
        build/usr/share/bash-completion/completions/xbps* \
        build/usr/share/zsh/site-functions/_xbps*

clean:
  #!/bin/sh
  set -eu
  if [ -d build ]; then chmod -R u+w build; fi
  if [ -d .iso ]; then chmod -R u+w .iso; fi
  rm -rf build .cache .iso .initrd vix.iso
