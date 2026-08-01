const std = @import("std");

const kernel = @import("kernel");
const cast = kernel.cast;
const types = kernel.util.types;
const bin = kernel.util.binary;

const memory = @import("memory.zig");
const vmm = @import("vmm.zig");
const pmm = @import("pmm.zig");
const buddy = @import("buddyAlloc.zig");

const lib = @import("lib");

const arch = @import("arch");
pub const Pte = arch.paging.Pte;
const cpu = arch.cpu;
const log = kernel.util.log;
const print = log.print;

const paging = @This();

pub const PTE_MAX_DEPTH = 5;
pub const PFE_MAX_DEPTH = 3;

/// Default PTE that is present, user, read, write, execute, with write back caching
pub var PTE_DEFAULTS : [PTE_MAX_DEPTH]Pte = undefined;
/// Default PFE that is present, read, write, execute, with write back caching
pub var PFE_DEFAULTS : [PFE_MAX_DEPTH]Pte = undefined;

pub const PTE_SIZE_BITS = 12;
pub const PTE_ENTRIES = 512;
pub const PTE_ENTRY_BITS = 9;

pub fn flushPages(info : *const kernel.SmpCall.CallInfo) void {
    var start = info.args[0];
    const end = info.args[1];

    while (start < end) : (start += types.SIZE_4KB) {
        arch.paging.flushPage(@ptrFromInt(start));
    }
}

pub fn flushAll(info : *kernel.SmpCall.CallInfo) void {
    _ = info;

    arch.paging.flushTlb();
}

pub const Ptable = struct {
    pte : [PTE_ENTRIES]Pte,

    /// Switches to this table and returns the old tables
    pub fn switchTo(this : *@This()) *@This() {
        const cur : *@This() = arch.paging.getPageTables();
        if(cur == this) return this;

        arch.paging.setPageTables(this);

        return cur;
    }
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

fn getPteType(pte : *Pte, level : anytype) enum {EMPTY, PFE, TABLE} {
    if(pte.getEmpty(level)) return .EMPTY;

    if (pte.getPresent(level)) {
        if (pte.getPfe(level))
            return .PFE;

        return .TABLE;
    }

    return .PFE;
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

fn pteInit(state : *PfeStateData, level : anytype, alloc : bool) ?*Pte {
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
                // Permissions are determined at frame, not table

                state.walk[level - 1] = cast.toPtr(*Ptable, page.toVirt().ptr());

                pte = pteInit(state, level - 1, alloc);
            },
            .TABLE => {
                state.walk[level - 1] = cast.toPtr(*Ptable, pte.?.getEntry(level).toVirt().ptr());
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

fn pteNext(state : *PfeStateData, level : anytype, alloc : bool) ?*Pte {
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
                // Permissions are determined at frame, not table
            },
            .TABLE => page = pte.getEntry(level),
            .PFE => continue,
        }

        const table = cast.toPtr(*Ptable, page.toVirt().ptr());
        state.walk[level - 1] = table;

        return &table.pte[entry];
    }
}

fn getNext(this : *PfeStateData) ?*Pte {
    while (true) {
        this.pfe = pteNext(this, this.level, false) orelse return null;
        if (getPteType(this.pfe.?, this.level) == .PFE)
            return this.pfe;
    }
}

fn pteUnmapNext(state : *PfeStateData, prior_unmapped : bool) ?Pte {
    if (!state.init)
        getNext();

    const pte = state.pfe orelse return null;
    const pfe = pte.*;
    pte.setEmpty(state.level);

    var cur_state = state.*;

    getNext();

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

const PfeStateData = struct {
    pfe : ?*Pte = null,             // The current PFE
    cur : memory.Vaddr,             // The address of the current PFE.
    walk : [PTE_MAX_DEPTH]*Ptable,  // Page tables in the walk to the current PFE.
    start : memory.Vaddr,           // Beginning of PFE iteration.
    end : memory.Vaddr,             // End limits of PFE iteration.
    level : u8,                     // The level all mapped, unmapped, and retrieved PFEs will be.
    init : bool = false,            // State has been initialized with first PFE and ptable walk.
    space : *vmm.VmSpace,
};

fn createPfeStateData(space : *vmm.VmSpace, start : memory.Vaddr, end : memory.Vaddr, level : PageLevel) PfeStateData {
    if ((start.val & bin.setBit(63)) ^ ((end.val - 1) & bin.setBit(63)) == 1)
        @panic("Attempted to page kernel and user memory in the same state!");

    const size = PageLevelToSize[@intFromEnum(level)];
    const new_start : memory.Vaddr = .{.val = bin.alignDown(start.val, size)};
    return .{
        .start = new_start,
        .end = .{.val = bin.alignUp(end.val, size)},
        .cur = new_start,
        .level = @intFromEnum(level),
        .walk = blk: {
            var walk : [PTE_MAX_DEPTH]*Ptable = undefined;
            walk[cpu.FEATURES.PAGE_TABLE_LEVELS - 1] = space.rootPt;
            break :blk walk;
        },
        .space = space,
    };
}

pub fn PfeState(comptime iterator : enum {MAP, UNMAP, GET}) type {
    return switch (iterator) {
        .GET => struct {
            data : PfeStateData,

            pub fn create(space : *vmm.VmSpace, start : memory.Vaddr, end : memory.Vaddr, level : PageLevel) @This() {
                return .{ .data = createPfeStateData(space, start, end, level), };
            }

            pub fn next(this : *@This()) ?*Pte {
                return getNext(&this.data);
            }
        },
        .MAP => struct {
            data : PfeStateData,

            pub fn create(space : *vmm.VmSpace, start : memory.Vaddr, end : memory.Vaddr, level : PageLevel) @This() {
                return .{ .data = createPfeStateData(space, start, end, level), };
            }

            pub fn next(this : *@This()) ?*Pte {
                return pteNext(&this.data, this.data.level, true);
            }
        },
        .UNMAP => struct {
            data : PfeStateData,
            priorUnmapped : bool,

            pub fn create(space : *vmm.VmSpace, start : memory.Vaddr, end : memory.Vaddr, priorUnmapped : bool, level : PageLevel) @This() {
                return .{
                    .data = createPfeStateData(space, start, end, level),
                    .priorUnmapped = priorUnmapped,
                };
            }

            pub fn next(this : *@This()) ?Pte {
                return pteUnmapNext(&this.data, this.priorUnmapped);
            }
        }
    };
}

pub fn mmioMap(start : memory.Paddr, size : usize, cache : PteCache) memory.Vaddr {
    var pstart : memory.Paddr = .asPhys(bin.alignDown(start.val, types.SIZE_4KB));

    const vstart = pstart.toVirt();
    const sizeAligned = bin.alignUp(size, types.SIZE_4KB);
    const vend : memory.Vaddr = .asVirt(vstart.val + sizeAligned);

    const area = kernel.pmalloc(vmm.VmArea);
    area.start = vstart;
    area.end = vend;
    area.flags.reserved = true;
    area.areaType = .MMIO;

    var mas = lib.linux.MapleTree.MaState.create(&kernel.kernelProcess.addrSpace.tree, vstart.val, vstart.val);
    mas.lock();

    if (mas.findRange(vend.val - 1) != null) {
        @panic("mm: MMIO mapping found an existing entry");
    }

    mas.val.index = vstart.val;
    mas.val.last = vend.val - 1;
    mas.store(area);

    mas.unlock();

    var pfeState = PfeState(.MAP).create(&kernel.kernelProcess.addrSpace, vstart, .asVirt(vstart.val + sizeAligned), .LEVEL_4KB);

    kernel.kernelProcess.addrSpace.spinlock.lock();
    defer kernel.kernelProcess.addrSpace.spinlock.unlock();

    while (pfeState.next()) |pfe| {
        pfe.* = PFE_DEFAULTS[0];
        pfe.setCache(0, cache);
        pfe.setEntry(0, pstart);
        pstart.val += types.SIZE_4KB;
    }

    return vstart;
}

pub fn printPtables(root_pt : *Ptable, level : anytype, min : anytype) void {
    outer: for (0..PTE_ENTRIES) |i| {
        const pte : *Pte = &root_pt.pte[i];

        switch (getPteType(pte, level)) {
            .EMPTY => continue :outer,
            .TABLE => {
                const page : memory.Paddr = pte.getEntry(level);
                const table : *Ptable = @ptrFromInt(page.toVirt().val);
                log.printChar(' ', (cpu.FEATURES.PAGE_TABLE_LEVELS - 1 - level) * 4);
                print("Table {d} 0x{X}\n", .{i, page.val});
                if (level - 1 >= min)
                    printPtables(table, level - 1, min);
            },
            .PFE => {
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
        default.setUser(level, true);
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