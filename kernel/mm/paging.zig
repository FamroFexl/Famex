const memory = @import("memory.zig");

const types = @import("kernel").util.types;

// Max page table levels
pub var PT_LEVEL : u8 = undefined;

// Packed page info, as small as possible
pub const page_info = struct {
    data : [3]u8,

    const data_layout = struct {
        flags : u8,
        order : u5,
        region : u11,
    };

    pub fn get_flags(self : page_info) u8 {
        const out : data_layout = @bitCast(self.data);
        return out.flags;
    }

    pub fn set_flags(self : page_info, flags : u8) void {
        const out : data_layout = @bitCast(self.data);
        out.flags = flags;
        self.data = @bitCast(out);
    }

    pub fn get_order(self : page_info) u5 {
        const out : data_layout = @bitCast(self.data);
        return out.order;
    }

    pub fn set_order(self : page_info, order : u5) void {
        const out : data_layout = @bitCast(self.data);
        out.order = order;
        self.data = @bitCast(out);
    }

    pub fn set_region(self : page_info, region : u11) void {
        const out : data_layout = @bitCast(self.data);
        out.region = region;
        self.data = @bitCast(out);
    }

    pub fn to_phys(self : *page_info) memory.paddr {
        return (@intFromPtr(self) - memory.PAGE_METADATA) / @sizeOf(page_info) * types.SIZE_4KB;
    }

    pub fn to_virt(self : *page_info) memory.vaddr {
        return self.to_phys().to_virt();
    }
};

comptime {
    if (@sizeOf(page_info) != 3) {
        @compileError("page_info is not 3 bytes!");
    }
}