cd ../zig-out/bin

zig build -Darch=x86_64

../../script/generate_iso.sh famex.elf

pid=$(lsof -t -i :1234)
if [ -n "$pid" ]; then
    kill -9 $pid
fi


qemu-system-x86_64 -L . --bios ../../limine/efi/x64/DEBUGX64_OVMF.fd -d cpu_reset,guest_errors -D qemu.log -debugcon stdio -global isa-debugcon.iobase=0x3f8 -accel tcg -rtc base=utc -display none -no-reboot -no-shutdown -cpu qemu64 -smp 1 -m 300M -s -S -cdrom ./famex.iso

