const kernel = @import("kernel");
const paging = kernel.mm.paging;
const mem = kernel.mm.memory;
const bin = kernel.util.binary;
const debug = @import("std").debug;

const reg = @import("arch").reg;
const PatType = reg.Pat.Layout.PatType;

const arch = @import("arch");
const cpu = @import("cpu.zig");

pub fn setPageTables(tables : *paging.Ptable) void {
    reg.Cr3.set(@bitCast(mem.Vaddr.asVirt(@intFromPtr(tables)).toPhys().val));
}

pub fn getPageTables() *paging.Ptable {
    return @ptrFromInt(mem.Paddr.asPhys(@bitCast(reg.Cr3.get())).toVirt().val);
}

pub fn flushTlb() void {
    reg.Cr3.set(reg.Cr3.get());
}

pub fn flushPage(page : *anyopaque) void {
    reg.tlbPageFlush(page);
}

pub const Pte = packed struct(u64) {
    present : bool,
    writable : bool,
    user : bool,
    pwt : bool,
    pcd : bool,
    accessed : bool,
    dirty : bool,
    bits : packed union(u1) {
        pfe : bool,   // PFE for non-4Kb pfe
        pat : bool,   // PAT for 4Kb pfe
        reserved : u1, // For 5-level page table
    },
    bits2 : packed union(u1) {
        global : bool,
        ignored : u1,
    },
    ignored : u2,
    restart : bool,
    bits3 : packed union(u1) {
        pat : bool,       // PAT for non-4Kb pfe
        reserved : u1,
    },
    reserved2 : u39,
    ignored2 : u7,
    bits4 : packed union(u4) {
        ignored : u4,
        prot_key : u4,  // Only used if enabled
    },
    no_execute : bool,

    comptime {
        debug.assert(@bitSizeOf(Pte) == 64);
    }

    fn setPat(pte : *Pte, level : anytype, pat : PatType) void {
        const bits = @intFromEnum(pat);
        pte.pwt = bin.getBit(0, bits);
        pte.pcd = bin.getBit(1, bits);

        if(level == 0) {
            pte.bits.pat = bin.getBit(2, bits);
        }
        else
            pte.bits3.pat = bin.getBit(2, bits);
    }

    fn getPat(pte : *Pte, level : anytype) PatType {
        var pat : u8 = 0;

        pat &= pte.pwt;
        pat &= (pte.pcd << 1);
        if(level == 0) {
            pat &= (pte.bits.pat << 2);
        }
        else
            pat &= (pte.bits3.pat << 2);

        return @enumFromInt(pat);
    }

    pub fn setOsBits(this : *@This(), bits : u64) void {
        this.ignored = @intCast(bits);
        this.ignored2 = @intCast(bits >> 2);
    }

    pub fn setCache(this : *@This(), level : anytype, cache : paging.PteCache) void {
        setPat(this, level,switch(cache) {
            .WRITE_BACK => .WRITE_BACK,
            .WRITE_COMBINING => .WRITE_COMBINING,
            .UNCACHED => .UNCACHEABLE,
        });
    }

    pub fn setWrite(this : *@This(), level : anytype, write : bool) void {
        _ = level;
        this.writable = write;
    }

    pub fn setRead(this : *@This(), level : anytype, read : bool) void {
        _ = this;
        _ = level;
        _ = read;
        return;
    }

    pub fn setExec(this : *@This(), level : anytype, exec : bool) void {
        _ = level;
        if (!arch.cpu.EXECUTE_PAGING_BIT) return;

        this.no_execute = !exec;
    }

    pub fn setPresent(this : *@This(), level : anytype, present : bool) void {
        _ = level;
        this.present = present;
    }

    pub fn setUser(this : *@This(), level : anytype, user : bool) void {
        _ = level;
        this.user = user;
    }

    pub fn setPfe(this : *@This(), level : anytype, pfe : bool) void {
        if(level > cpu.FEATURES.MAX_PAGE_SIZE) return;

        if(level == 0) return;
        this.bits.pfe = pfe;
    }

    pub fn setEntry(this : *@This(), level : anytype, entry : mem.Paddr) void {
        const mask : u64 = mem.PHYS_ADDR_SIZE & (~bin.setBits((@as(u64, level) * paging.PTE_ENTRY_BITS * @as(u64, @intFromBool(this.getPfe(level)))) + paging.PTE_SIZE_BITS));
        this.* = @bitCast((@as(u64, @bitCast(this.*)) & ~mask) | (entry.val & mask));
    }

    pub fn setEmpty(this : *@This(), level : anytype) void {
        _ = level;
        this.* = @bitCast(@as(u64, 0));
    }

    pub fn setAccessed(this : *@This(), level : anytype, accessed : bool) void {
        _ = level;
        this.accessed = accessed;
    }

    pub fn setGlobal(this : *@This(), level : anytype, global : bool) void {
        debug.assert(this.getPfe(level));

        this.bits2.global = global;
    }

    pub fn setDirty(this : *@This(), level : anytype, dirty : bool) void {
        debug.assert(this.getPfe(level));

        this.dirty = dirty;
    }

    pub fn getNumOsBits() u8 {
        // This is the maximum number of consistent bits across all Pte types
        return 9;
    }

    pub fn getOsBits(this : @This()) u64 {
        var bits : u9 = 0;
        bits |= @intCast(this.ignored);
        bits |= @intCast(this.ignored2 << 2);

        return @intCast(bits);
    }

    pub fn getCache(this : *@This(), level : anytype) paging.PteCache {
        return switch(getPat(this, level)) {
            .WRITE_BACK => .WRITE_BACK,
            .WRITE_COMBINING => .WRITE_COMBINING,
            .UNCACHEABLE => .UNCACHED,
        };
    }

    pub fn getWrite(this : *@This(), level : anytype) bool {
        _ = level;
        return this.writable;
    }

    pub fn getRead(this : *@This(), level : anytype) bool {
        _ = this;
        _ = level;
        return true;
    }

    pub fn getExec(this : *@This(), level : anytype) bool {
        _ = level;
        if (!arch.cpu.EXECUTE_PAGING_BIT) return true;

        return !this.no_execute;
    }

    pub fn getPresent(this : *@This(), level : anytype) bool {
        _ = level;
        return this.present;
    }

    pub fn getUser(this : *@This(), level : anytype) bool {
        _ = level;
        return this.user;
    }

    pub fn getPfe(this : *@This(), level : anytype) bool {
        if(level == 0) return true;
        return this.bits.pfe;
    }

    pub fn getEntry(this : *@This(), level : anytype) mem.Paddr {
        const mask : u64 = mem.PHYS_ADDR_SIZE & (~bin.setBits((level * paging.PTE_ENTRY_BITS * @as(u64, @intFromBool(this.getPfe(level)))) + paging.PTE_SIZE_BITS));
        return .{.val = @as(u64, @bitCast(this.*)) & mask,};
    }

    pub fn getEmpty(this : *@This(), level : anytype) bool {
        _ = level;
        return bin.isZero(this.*);
    }

    pub fn getAccessed(this : *@This(), level : anytype) bool {
        _ = level;
        return this.accessed;
    }

    pub fn getGlobal(this : *@This(), level : anytype) bool {
        debug.assert(this.getPfe(level));

        return this.global;
    }

    pub fn getDirty(this : *@This(), level : anytype) bool {
        debug.assert(this.getPfe(level));

        return this.dirty;
    }
};