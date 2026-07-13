#!/usr/bin/env sh
KERNEL_BIN=$1
KERNEL_NAME=${KERNEL_BIN%.*}
KERNEL_ISO=${KERNEL_NAME}.iso

mkdir -p isodir/boot/limine
cp -v "${KERNEL_BIN}" isodir/boot/${KERNEL_BIN}
#cp -v ../limine/limine-bios.sys ../limine/limine-bios-cd.bin ../limine/limine-uefi-cd.bin isodir/boot/limine
cp -v ../../limine/limine-uefi-cd.bin isodir/boot/limine

mkdir -p isodir/boot/modules
cp -v ../../zig-out/bin/testProc.elf isodir/boot/modules

#../modules/comp_exec.sh
echo "timeout: 0
/${KERNEL_NAME}
  protocol: limine
	path: boot():/boot/${KERNEL_BIN}
	module_path: boot():/boot/modules/testProc.elf
" > isodir/boot/limine/limine.conf

#module_path: boot():/boot/posix_tests

mkdir -p isodir/EFI/BOOT
cp -v ../../limine/BOOTX64.EFI isodir/EFI/BOOT/

#xorriso -as mkisofs -R -r -J -b boot/limine/limine-bios-cd.bin \
 # -no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus \
 # -apm-block-size 2048 --efi-boot boot/limine/limine-uefi-cd.bin \
 # -efi-boot-part --efi-boot-image --protective-msdos-label \
# isodir -o ${KERNEL_ISO}

xorriso -as mkisofs -R -r -J --efi-boot boot/limine/limine-uefi-cd.bin \
  -efi-boot-part --efi-boot-image -no-emul-boot \
  isodir -o ${KERNEL_ISO}

#../limine/limine bios-install ${KERNEL_ISO}
rm -rf isodir