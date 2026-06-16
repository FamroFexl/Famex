cd ../zig-out/bin

lldb -o "target create famex.elf" -o "script import time; time.sleep(2)" -o "gdb-remote 1234"