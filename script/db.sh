cd ../zig-out/bin

lldb -o "target create famex.elf" -o "gdb-remote 1234"