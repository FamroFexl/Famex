const std = @import("std");

const kernel = @import("kernel");
const types = kernel.util.types;
const bin = kernel.util.binary;

const memory = @import("memory.zig");
const vmm = @import("vmm.zig");
const pmm = @import("pmm.zig");
const buddy = @import("buddyAlloc.zig");

const arch = @import("arch");
pub const Pte = arch.paging.Pte;
const cpu = arch.cpu;
const log = kernel.util.log;
const print = log.print;

pub const PTE_MAX_DEPTH = 5;
pub const PFE_MAX_DEPTH = 3;

pub var PTE_DEFAULTS : [PTE_MAX_DEPTH]Pte = undefined;
pub var PFE_DEFAULTS : [PFE_MAX_DEPTH]Pte = undefined;

pub const PTE_SIZE_BITS = 12;
pub const PTE_ENTRIES = 512;
pub const PTE_ENTRY_BITS = 9;

pub const Ptable = struct {
    pte : [PTE_ENTRIES]Pte,
};

pub const PteCache = enum(u4) {
    WRITE_BACK,
    WRITE_COMBINING,
    UNCACHED,
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
    const DataLayout = packed struct(u24) {
        flags : Flags,
        order : u5,
        region : u11,
    };

    pub fn getData(this : @This()) DataLayout {
        return @bitCast(this);
    }

    pub fn setData(this : *@This(), data : DataLayout) void {
        this.*.data = @bitCast(data);
    }

    pub fn toPhys(this : *@This()) memory.Paddr {
        return .{.val = ((@intFromPtr(this) - memory.PAGE_METADATA) / @sizeOf(@This())) * types.SIZE_4KB};
    }

    pub fn toVirt(this : *@This()) memory.Vaddr {
        return this.toPhys().toVirt();
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

const PageOrder = enum(u8) {
    ORDER_4KB = 0,
    ORDER_2MB = 9,
    ORDER_1GB = 18,
};

const PageLevel = enum(u2) {
    LEVEL_4KB = 0,
    LEVEL_2MB = 1,
    LEVEL_1GB = 2,
};

const PageLevelToSize = [_]usize{
    types.SIZE_4KB,
    types.SIZE_2MB,
    types.SIZE_1GB,
    types.SIZE_512GB,
    types.SIZE_256TB,
    types.SIZE_128PB,
};

fn pteInit(state : *PfeState, level : anytype, alloc : bool) ?*Pte {
    const entry = getPtableEntry(state.cur, level);

    if (level == state.level)
        return &state.walk[level].pte[entry];

    var pte : ?*Pte = undefined;
    for(entry..PTE_ENTRIES) |i| {
        pte = &state.walk[level].pte[i];

        switch (getPteType(pte.?, level)) {
            .EMPTY => {
                if (!alloc)
                    continue;

                const page = buddy.zallocPage4k();

                pte.?.* = PTE_DEFAULTS[level];
                pte.?.setEntry(level, page);

                state.walk[level - 1] = bin.castPtr(*Ptable, page.toVirt().ptr());

                pte = pteInit(state, level - 1, alloc);
            },
            .TABLE => {
                state.walk[level - 1] = bin.castPtr(*Ptable, pte.?.getEntry(level).toVirt().ptr());
                pte = pteInit(state, level - 1, alloc);
            },
            .PFE => continue,
        }

        if (pte != null)
            break;

        const size = PageLevelToSize[level];
        state.cur = .{.val = bin.alignDown(state.cur.val, size) + size};

        if (state.cur.val >= state.end.val)
            return null;
    }

    return pte;
}

fn pteNext(state : *PfeState, level : anytype, alloc : bool) ?*Pte {
    if (!state.init) {
        state.init = true;
        state.pfe = pteInit(state, cpu.FEATURES.PAGE_TABLE_LEVELS - 1, alloc);
        return state.pfe;
    }

    const entry = getPtableEntry(state.cur, level);
    var pte : *Pte = undefined;

    while (true) {
        // We are beyond range, we need to go up a level
        if (entry == PTE_ENTRIES - 1) {
            pte = pteNext(state, level + 1, alloc) orelse return null;

            const size = PageLevelToSize[level];
            state.cur.val = bin.alignDown(state.cur.val, size);
        }
        // We are in range
        else {
            const size = PageLevelToSize[level];
            state.cur.val += size;

            if (state.cur.val >= state.end.val)
                return null;

            pte = &state.walk[level].pte[entry];
        }

        if (level == state.level)
            return pte;

        var page : memory.Paddr = undefined;
        switch (getPteType(pte, level)) {
            .EMPTY => {
                if (!alloc)
                    continue;

                page = buddy.zallocPage4k();

                pte.* = PTE_DEFAULTS[level];
                pte.setEntry(level, page);
            },
            .TABLE => page = pte.getEntry(level),
            .PFE => continue,
        }

        const table = bin.castPtr(*Ptable, page.toVirt().ptr());
        state.walk[level - 1] = table;

        return &table.pte[entry];
    }
}

fn pteUnmapNext(state : *PfeState, prior_unmapped : bool) ?Pte {
    if (!state.init)
        state.getNext();

    const pte = state.pfe orelse return null;
    const pfe = pte.*;
    pte.setEmpty(state.level);

    var cur_state = state.*;

    state.getNext();

    // See if any optimizations can be applied before a manual scan.
    var level : u8 = undefined;
    if (prior_unmapped) {
        // Get the highest page table level that changed between addresses
        const diff = cur_state.cur.val ^ state.cur.val;
        if (diff != 0) {
            level = (63 - PTE_SIZE_BITS - @clz(diff)) / PTE_ENTRY_BITS;
        }
        else {
            level = state.level;
        }

        // Free all levels that we know are empty and don't need to scan
        for((state.level + 1)..(level + 1)) |i| {
            const entry = getPtableEntry(cur_state.cur, i);
            const next_pte = &cur_state.walk[i].pte[entry];
            const table = next_pte.getEntry(level);
            buddy.freePage4K(table);
        }
    }
    else {
        level = state.level;
    }

    // Manually scan over remaining levels
    outer: for ((level + 1)..cpu.FEATURES.PAGE_TABLE_LEVELS) |i| {
        const entry = getPtableEntry(cur_state.cur, i);
        const next_pte = &cur_state.walk[i].pte[entry];
        const table_entry = next_pte.getEntry(level);
        const table : *Ptable = @ptrCast(table_entry.toVirt().ptr());

        for (0..PTE_ENTRIES) |j| {
            // Does the entry exist?
            if (!table.pte[j].getEmpty(i - 1))
                break :outer;
        }

        buddy.freePage4k(table_entry);
        next_pte.* = 0;
    }

    return pfe;
}

const PfeIterator = enum {
    MAP,
    UNMAP,
    GET,
};

pub const PfeState = struct {
    pfe : ?*Pte,                     // The current PFE
    cur : memory.Vaddr,             // The address of the current PFE.
    walk : [PTE_MAX_DEPTH]*Ptable,  // Page tables in the walk to the current PFE.
    start : memory.Vaddr,           // Beginning of PFE iteration.
    end : memory.Vaddr,             // End limits of PFE iteration.
    level : u8,                     // The level all mapped, unmapped, and retrieved PFEs will be.
    init : bool,                    // State has been initialized with first PFE and ptable walk.
    iterator : PfeIterator,
    space : *vmm.VmSpace,

    pub fn create(iterator : PfeIterator, space : *vmm.VmSpace, start : memory.Vaddr, end : memory.Vaddr, level : PageLevel) PfeState {
        const size = PageLevelToSize[@intFromEnum(level)];
        const new_start : memory.Vaddr = .{.val = bin.alignUp(start.val, size)};
        return .{
            .pfe = null,
            .start = new_start,
            .end = .{.val = bin.alignDown(end.val, size)},
            .cur = new_start,
            .level = @intFromEnum(level),
            .walk = blk: {
                var walk : [PTE_MAX_DEPTH]*Ptable = undefined;
                walk[cpu.FEATURES.PAGE_TABLE_LEVELS - 1] = space.rootPt;
                break :blk walk;
            },
            .init = false,
            .iterator = iterator,
            .space = space,
        };
    }

    pub fn getNext(state : *@This()) ?*Pte {
        std.debug.assert(state.iterator == .GET);

        state.pfe = pteNext(state, state.level, false);
        while (state.pfe and getPteType(state.level, state.pfe) != .PFE) {
            state.pfe = pteNext(state, state.level, false);
        }

        return state.pfe;
    }

    pub fn mapNext(state : *@This()) ?*Pte {
        std.debug.assert(state.iterator == .MAP);

        return pteNext(state, state.level, true);
    }

    pub fn unmapNext(state : *@This(), prior_unmapped : bool) ?Pte {
        std.debug.assert(state.iterator == .UNMAP);

        return pteUnmapNext(state, prior_unmapped);
    }
};

pub fn printPtables(root_pt : *Ptable, level : anytype, min : anytype) void {
    outer: for (0..PTE_ENTRIES) |i| {
        const pte : *Pte = &root_pt.pte[i];

        switch (getPteType(pte, level)) {
            PteType.EMPTY => continue :outer,
            PteType.TABLE => {
                const page : memory.Paddr = pte.getEntry(level);
                const table : *Ptable = @ptrFromInt(page.toVirt().val);
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
            memory.memset(@ptrFromInt(page.toVirt().val), types.SIZE_4KB, 0);
            current_pte.setEntry(i, page);
        }

        cur_pt = @ptrFromInt(current_pte.getEntry(i).toVirt().val);
        current_pte = &cur_pt.pte[getPtableEntry(addr, i - 1)];
    }

    current_pte.* = pte;
}

// Switches to new table and returns the old tables
pub fn switchPageTables(new_tables : *Ptable) *Ptable {
    const cur : *Ptable = arch.paging.getPageTables();
    if(cur == new_tables) return new_tables;

    arch.paging.setPageTables(new_tables);

    return cur;
}

pub fn setupRootPt(rootPt : *Ptable) void {
    const level = cpu.FEATURES.PAGE_TABLE_LEVELS - 1;
    for ((PTE_ENTRIES/2)..PTE_ENTRIES) |i| {
        if (rootPt.pte[i].getPresent(level)) continue;

        rootPt.pte[i] = PTE_DEFAULTS[level];
        rootPt.pte[i].setEntry(level, kernel.zallocPage4k());
    }
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