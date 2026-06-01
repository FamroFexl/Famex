//const fmt = @import("std").fmt.bufPrint;


pub fn outb(port: u16, value: u8) void {
    asm volatile (
        "outb %[val], %[port]"
        :
        : [val] "{al}" (value),
          [port] "{dx}" (port),
    );
}

pub export fn kernel_main() void {
    for(0..100) |_| {
        outb(0x3F8, '5');
    }

}