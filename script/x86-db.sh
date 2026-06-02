cd ../zig-out/bin

zig build -Darch=x86_64

../../script/generate_iso.sh famex.elf

pid=$(lsof -t -i :1234)
if [ -n "$pid" ]; then
    kill -9 $pid
fi

#qemu-system-x86_64 -nographic -m 300M -no-reboot -no-shutdown -s -S -d int,guest_errors -D qemu.log -cdrom ./BaseOS.iso
qemu-system-x86_64 -L . --bios ../../limine/efi/x64/DEBUGX64_OVMF.fd -nographic -cpu qemu64 -accel tcg -smp 1 -m 300M -no-reboot -no-shutdown -s -S -d cpu_reset,int,guest_errors -D qemu.log -cdrom ./famex.iso


