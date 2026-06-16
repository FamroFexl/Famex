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
    WRITE_BACK,
    WRITE_COMBINING,
    UNCACHED,
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
pub const PageInfo = extern struct {
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

    pub fn getData(self : @This()) DataLayout {
        return @bitCast(self);
    }

    pub fn setData(self : *@This(), data : DataLayout) void {
        self.*.data = @bitCast(data);
    }

    pub fn toPhys(self : *@This()) memory.Paddr {
        return .{.val = ((@intFromPtr(self) - memory.PAGE_METADATA) / @sizeOf(@This())) * types.SIZE_4KB};
    }

    pub fn toVirt(self : *@This()) memory.Vaddr {
        return self.toPhys().to_virt();
    }

    comptime {
        if (@sizeOf(PageInfo) != 3) {
            @compileError("PageInfo is not 3 bytes!");
        }
    }
};

pub fn getPtableEntry(addr : memory.Vaddr, level : anytype) u9 {
    return @intCast(bin.getBits(PTE_ENTRY_BITS, PTE_SIZE_BITS + level * PTE_ENTRY_BITS, addr.val));
}

const PteType = enum {
    EMPTY,
    PFE,
    TABLE
};

fn getPteType(pte : *Pte, level : anytype) PteType {
    if(pte.getEmpty(level)) return PteType.EMPTY;

    if (pte.getPresent(level)) {
        if (pte.getPfe(level))
            return PteType.PFE;

        return PteType.TABLE;
    }

    return PteType.PFE;
}

pub fn printPtables(root_pt : *Ptable, level : anytype, min : anytype) void {
    outer: for (0..PTE_ENTRIES) |i| {
        const pte : *Pte = &root_pt.pte[i];

        switch (getPteType(pte, level)) {
            PteType.EMPTY => continue :outer,
            PteType.TABLE => {
                const page : memory.Paddr = pte.getEntry(level);
                const table : *Ptable = @ptrFromInt(page.to_virt().val);
                log.printChar(' ', (cpu.FEATURES.PAGE_TABLE_LEVELS - 1 - level) * 4);
                print("Table {d} 0x{X}\n", .{i, page.val});
                if (level - 1 >= min)
                    printPtables(table, level - 1, min);
            },
            PteType.PFE => {
                const page : memory.Paddr = pte.getEntry(level);
                log.printChar(' ', (cpu.FEATURES.PAGE_TABLE_LEVELS - 1 - level) * 4);
                print("Page {d} 0x{X}\n", .{i, page.val});
            },
        }
    }
}

pub fn mapBootPage(addr : memory.Vaddr, pte : Pte, level : u8, root_pt : *Ptable) void {
    var cur_pt : *Ptable = root_pt;

    var i = cpu.FEATURES.PAGE_TABLE_LEVELS - 1;
    var current_pte = &cur_pt.pte[getPtableEntry(addr, i)];

    while(i > level) : (i -= 1) {
        if(!current_pte.getPresent(i)) {
            current_pte.* = PTE_DEFAULTS[i];
            const page : memory.Paddr = pmm.allocBootPage();
            memory.memset(@ptrFromInt(page.to_virt().val), types.SIZE_4KB, 0);
            current_pte.setEntry(i, page);
        }

        cur_pt = @ptrFromInt(current_pte.getEntry(i).to_virt().val);
        current_pte = &cur_pt.pte[getPtableEntry(addr, i - 1)];
    }

    current_pte.* = pte;
}

// Switches to new table and returns the old tables
pub fn switchPageTables(new_tables : *Ptable) *Ptable {
    const cur : *Ptable = arch.paging.get_page_tables();
    if(cur == new_tables) return new_tables;

    arch.paging.set_page_tables(new_tables);

    return cur;
}

fn setupPtes() void {
    for(1..cpu.FEATURES.PAGE_TABLE_LEVELS) |level| {
        const default = &PTE_DEFAULTS[level];
        default.setPresent(level, true);
        default.setCache(level, PteCache.WRITE_BACK);
        default.setPfe(level, false);
        default.setAccessed(level, false);
        default.setUser(level, false);
        default.setRead(level, true);
        default.setWrite(level, true);
        default.setExec(level, true);
    }

    for(0..(cpu.FEATURES.MAX_PAGE_SIZE + 1)) |level| {
        const default = &PFE_DEFAULTS[level];
        default.setPresent(level, true);
        default.setCache(level, PteCache.WRITE_BACK);
        default.setPfe(level, true);
        default.setAccessed(level, false);
        default.setUser(level, false);
        default.setRead(level, true);
        default.setWrite(level, true);
        default.setExec(level, true);
    }
}

pub fn setup() void {
    setupPtes();
}