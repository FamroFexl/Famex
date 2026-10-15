pkill -9 -f qemu-system-x86_64

set -e

zig build -Darch=x86_64

cd ../zig-out/bin

../../script/generate_iso.sh famex.elf

# -cpu DiamondRapids,la57=false
# -cpu GraniteRapids,la57=false
# -cpu ClearwaterForest
# -cpu Broadwell

qemu-system-x86_64 -L . --bios ../../limine/efi/x64/DEBUGX64_OVMF.fd -d cpu_reset,guest_errors -D qemu.log -debugcon stdio -global isa-debugcon.iobase=0x3f8 -accel tcg -rtc base=utc -display none -no-reboot -no-shutdown -cpu ClearwaterForest -smp 1 -m 300M -cdrom ./famex.iso