cd ../zig-out/bin

lldb -o "target create famex.elf" -o "target modules add testProc.elf" -o "script import time; time.sleep(1)" -o "gdb-remote 1234"