Vix is a Linux distribution which uses Void rootfs and Nix package manager.

## How do I install?
1. Clone the repo
2. Type `just metal`, you will get `vix.iso` shortly.
3. Flash the ISO to your memory stick
4. Boot it up
5. Login as root:vix, partition your drive.
6. Mount your root to `/mnt` and ESP (for EFI) to `/mnt/boot`
7. If you want, you can download the latest kernel and firmware using `vix kernel` and `vix firmware`
8. Run `vix-install /mnt [optionally blockdev for BIOS legacy installation]`
9. Reboot and profit

## Just
Available recipes:
- clean -- clean workdir from build artifacts
- getroot -- download Void rootfs
- merge -- merge Void rootfs and `over` overlay to `build` directory
- install-nix -- install Nix PM under chroot to `build`
- base -- install needed XBPS packages under chroot to `build`
- remove-xbps -- Remove XBPS PM. Optional one, never called automatically
- iso -- make an ISO
- metal -- make an ISO with some firmware stuff baked

## Downsides of Vix
- xbps is used for PAM stack and some other system-deep things (PM can be removed, but not the packages)
- Nix profiles are Nix profiles. Sometimes you need tinkering
- Wanna add a service? Write runit scripts by yourself, Nixpkgs provide none.
