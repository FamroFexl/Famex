/opt/homebrew/opt/llvm/bin/clang --target=x86_64-unknown-none-elf -g -gdwarf-4 -c -o entry.o entry.s
/opt/homebrew/Cellar/lld/20.1.7/bin/ld.lld -T linker.ld -o ../../zig-out/bin/testProc.elf entry.o # -n -Wl,-z noseparate-code
