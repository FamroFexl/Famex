const kernel = @import("kernel");
const types = kernel.util.types;
const bin = kernel.util.binary;

const memory = @import("memory.zig");
const vmm = @import("vmm.zig");
const pmm = @import("pmm.zig");

const arch = @import("arch");
pub const Pte = arch.paging.Pte;
const cpu = arch.cpu;
const log = kernel.util.log;
const print = log.print;

pub const PTE_MAX_DEPTH = 5;
pub const PFE_MAX_DEPTH = 3;

pub var PTE_DEFAULTS : [PTE_MAX_DEPTH]Pte = undefined;
pub var PFE_DEFAULTS : [PFE_MAX_DEPTH]Pte = undefined;

pub const PteCache = enum(u4) {
    WRITE_BACK = 0,
    WRITE_COMBINING = 1,
    UNCACHED = 2,
};

pub const PTE_SIZE_BITS = 12;
pub const PTE_ENTRIES = 512;
pub const PTE_ENTRY_BITS = 9;

pub const Ptable = struct {
    pte : [PTE_ENTRIES]Pte,
};

/// Packed page info, as small as possible.
/// This is the main memory hog, since one of these
/// exists for every 4096 bytes
pub const PageInfo = struct {
    data : [3]u8,

    const Flags = packed struct(u8) {
        free : bool,
        pad : u7 = undefined,
    };

    /// Somehow, packed structs require pow2 aligned types, so we
    /// can't have a packed struct with an arbitrary number of bytes.
    const DataLayout = packed struct {
        flags : Flags,
        order : u5,
        region : u11,
    };

    pub fn get_data(self : @This()) DataLayout {
        return @bitCast(self);
    }

    pub fn set_data(self : *@This(), data : DataLayout) void {
        self.*.data = @bitCast(data);
    }

    pub fn to_phys(self : *@This()) memory.Paddr {
        return .{.val = ((@intFromPtr(self) - memory.PAGE_METADATA) / @sizeOf(@This())) * types.SIZE_4KB};
    }

    pub fn to_virt(self : *@This()) memory.Vaddr {
        return self.to_phys().to_virt();
    }

    comptime {
        if (@sizeOf(PageInfo) != 3) {
            @compileError("PageInfo is not 3 bytes!");
        }
    }
};

pub fn get_ptable_entry(addr : memory.Vaddr, level : anytype) u9 {
    return @intCast(bin.get_bits(PTE_ENTRY_BITS, PTE_SIZE_BITS + level * PTE_ENTRY_BITS, addr.val));
}

const PteType = enum {
    EMPTY,
    PFE,
    TABLE
};

fn get_pte_type(pte : *Pte, level : anytype) PteType {
    if(pte.get_empty(level)) return PteType.EMPTY;

    if (pte.get_present(level)) {
        if (pte.get_pfe(level))
            return PteType.PFE;

        return PteType.TABLE;
    }

    return PteType.PFE;
}

pub fn print_ptables(root_pt : *Ptable, level : anytype, min : anytype) void {
    outer: for (0..PTE_ENTRIES) |i| {
        const pte : *Pte = &root_pt.pte[i];

        switch (get_pte_type(pte, level)) {
            PteType.EMPTY => continue :outer,
            PteType.TABLE => {
                const page : memory.Paddr = pte.get_entry(level);
                const table : *Ptable = @ptrFromInt(page.to_virt().val);
                log.print_char(' ', (cpu.FEATURES.PAGE_TABLE_LEVELS - 1 - level) * 4);
                print("Table {d} 0x{X}\n", .{i, page.val});
                if (level - 1 >= min)
                    print_ptables(table, level - 1, min);
            },
            PteType.PFE => {
                const page : memory.Paddr = pte.get_entry(level);
                log.print_char(' ', (cpu.FEATURES.PAGE_TABLE_LEVELS - 1 - level) * 4);
                print("Page {d} 0x{X}\n", .{i, page.val});
            },
        }
    }
}

pub fn map_boot_page(addr : memory.Vaddr, pte : Pte, level : u8, root_pt : *Ptable) void {
    var cur_pt : *Ptable = root_pt;

    var i = cpu.FEATURES.PAGE_TABLE_LEVELS - 1;
    var current_pte = &cur_pt.pte[get_ptable_entry(addr, i)];

    while(i > level) : (i -= 1) {
        if(!current_pte.get_present(i)) {
            current_pte.* = PTE_DEFAULTS[i];
            const page : memory.Paddr = pmm.alloc_boot_page();
            memory.memset(@ptrFromInt(page.to_virt().val), types.SIZE_4KB, 0);
            current_pte.set_entry(i, page);
        }

        cur_pt = @ptrFromInt(current_pte.get_entry(i).to_virt().val);
        current_pte = &cur_pt.pte[get_ptable_entry(addr, i - 1)];
    }

    current_pte.* = pte;
}

// Switches to new table and returns the old tables
pub fn switch_page_tables(new_tables : *Ptable) *Ptable {
    const cur : *Ptable = arch.paging.get_page_tables();
    if(cur == new_tables) return new_tables;

    arch.paging.set_page_tables(new_tables);

    return cur;
}

fn setup_ptes() void {
    for(1..cpu.FEATURES.PAGE_TABLE_LEVELS) |level| {
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

    for(0..(cpu.FEATURES.MAX_PAGE_SIZE + 1)) |level| {
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