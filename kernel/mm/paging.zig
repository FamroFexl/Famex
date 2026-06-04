const kernel = @import("kernel");
const types = kernel.util.types;
const bin = kernel.util.binary;

const memory = @import("memory.zig");
const vmm = @import("vmm.zig");
const pmm = @import("pmm.zig");

const arch = @import("arch");
pub const Pte = arch.paging.Pte;
const cpu = arch.cpu;

pub const PTE_MAX_DEPTH = 5;
pub const PFE_MAX_DEPTH = 3;

pub var PTE_DEFAULTS : [PTE_MAX_DEPTH]Pte = undefined;
pub var PFE_DEFAULTS : [PFE_MAX_DEPTH]Pte = undefined;


pub const PteCache = enum {
    WRITE_BACK,
    WRITE_COMBINING,
    UNCACHED
};

pub const PTE_SIZE_BITS = 12;
pub const PTE_ENTRIES = 512;
pub const PTE_ENTRY_BITS = 9;

pub const Ptable = struct {
    pte : [PTE_ENTRIES]Pte,
};

// Max page table levels
pub var PT_LEVELS : u8 = undefined;

// Packed page info, as small as possible
pub const PageInfo = struct {
    data : [3]u8,

    const DataLayout = struct {
        flags : u8,
        order : u5,
        region : u11,
    };

    pub fn get_flags(self : @This()) u8 {
        const out : DataLayout = @bitCast(self.data);
        return out.flags;
    }

    pub fn set_flags(self : @This(), flags : u8) void {
        const out : DataLayout = @bitCast(self.data);
        out.flags = flags;
        self.data = @bitCast(out);
    }

    pub fn get_order(self : @This()) u5 {
        const out : DataLayout = @bitCast(self.data);
        return out.order;
    }

    pub fn set_order(self : @This(), order : u5) void {
        const out : DataLayout = @bitCast(self.data);
        out.order = order;
        self.data = @bitCast(out);
    }

    pub fn set_region(self : @This(), region : u11) void {
        const out : DataLayout = @bitCast(self.data);
        out.region = region;
        self.data = @bitCast(out);
    }

    pub fn to_phys(self : *@This()) memory.Paddr {
        return (@intFromPtr(self) - memory.PAGE_METADATA) / @sizeOf(@This()) * types.SIZE_4KB;
    }

    pub fn to_virt(self : *@This()) memory.Vaddr {
        return self.to_phys().to_virt();
    }

    comptime {
        if (@sizeOf(PageInfo) != 3) {
            @compileError("page_info is not 3 bytes!");
        }
    }
};

fn get_ptable_entry(addr : u64, level : anytype) u16 {
    return @intCast(bin.get_bits(PTE_ENTRY_BITS, PTE_SIZE_BITS + level * PTE_ENTRY_BITS, addr));
}

pub fn map_boot_page(addr : u64, pte : Pte, level : u8, root_pt : *Ptable) void {
    var cur_pt : *Ptable = root_pt;

    var current_pte = &cur_pt.pte[get_ptable_entry(addr, PT_LEVELS - 1)];

    for((PT_LEVELS - 1)..level) |i| {
        if(!current_pte.get_present(i)) {
            current_pte.* = PTE_DEFAULTS[i];
            var page : memory.Paddr = pmm.alloc_boot_page();
            memory.memset(@ptrFromInt(page.to_virt().val), types.SIZE_4KB, 0);
            current_pte.set_entry(i, page);
        }

        cur_pt = @ptrFromInt(current_pte.get_entry(i).to_virt().val);
        current_pte = &cur_pt.pte[get_ptable_entry(addr, i)];
    }

    current_pte.* = pte;
}

fn setup_ptes() void {
    for(1..PT_LEVELS) |level| {
        const default = &PTE_DEFAULTS[level];
        default.set_present(level, true);
        default.set_cache(level, PteCache.WRITE_BACK);
        default.set_pfe(level, false);
        default.set_accessed(level, false);
        default.set_user(level, false);
        default.set_read(level, true);
        default.set_write(level, true);
        default.set_exec(level, true);
    }


    for(0..cpu.FEATURES.max_page_size) |level| {
        const default = &PFE_DEFAULTS[level];
        default.set_present(level, true);
        default.set_cache(level, PteCache.WRITE_BACK);
        default.set_pfe(level, true);
        default.set_accessed(level, false);
        default.set_user(level, false);
        default.set_read(level, true);
        default.set_write(level, true);
        default.set_exec(level, true);
    }
}

pub fn setup_paging() void {
    setup_ptes();
}