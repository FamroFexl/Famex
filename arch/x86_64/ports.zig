pub fn out(port : u16, value : anytype) void {
    switch (@TypeOf(value)) {
        u8 => asm volatile ("outb %al, %dx" :: [v] "{al}" (value), [p] "{dx}" (port),),
        u16 => asm volatile ("outw %ax, %dx" :: [v] "{ax}" (value), [p] "{dx}" (port),),
        u32 => asm volatile ("outl %eax, %dx" :: [v] "{eax}" (value), [p] "{dx}" (port),),
        else => @compileError("Bad port out type"),
    }
}

pub fn in(port: u16, comptime T: type) T {
    return switch (T) {
        u8 => asm volatile ("inb %dx, %al" : [ret] "={al}" (-> u8) : [p] "{dx}" (port),),
        u16 => asm volatile ("inw %dx, %ax" : [ret] "={ax}" (-> u16) : [p] "{dx}" (port),),
        u32 => asm volatile ("inl %dx, %eax" : [ret] "={eax}" (-> u32) : [p] "{dx}" (port),),
        else => @compileError("Bad port in type"),
    };
}