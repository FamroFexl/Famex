cd ../zig-out/bin

set -e

zig build -Darch=x86_64

../../script/generate_iso.sh famex.elf

qemu-system-x86_64 -L . --bios ../../limine/efi/x64/DEBUGX64_OVMF.fd -d cpu_reset,guest_errors -D qemu.log -serial stdio -accel tcg -rtc base=utc -display none -no-reboot -no-shutdown -cpu qemu64 -smp 1 -m 300M -cdrom ./Famex.iso
