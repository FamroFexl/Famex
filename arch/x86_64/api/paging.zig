const kernel = @import("kernel");
const paging = kernel.mm.paging;
const mem = kernel.mm.memory;
const bin = kernel.util.binary;
const debug = @import("std").debug;

const reg = @import("arch").reg;
const PatType = reg.Pat.Layout.PatType;

const cpu = @import("cpu.zig");

pub fn set_page_tables(tables : *paging.Ptable) void {
    reg.Cr3.set(@bitCast(mem.Vaddr.as_virt(@intFromPtr(tables)).to_phys().val));
}

pub fn get_page_tables() *paging.Ptable {
    return @ptrFromInt(mem.Paddr.as_phys(@bitCast(reg.Cr3.get())).to_virt().val);
}

pub fn flush_tlb() void {
    reg.Cr3.set(reg.Cr3.get());
}

pub fn flush_page(page : *anyopaque) void {
    reg.tlb_page_flush(page);
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

    pub fn setOsBits(self : *@This(), bits : u64) void {
        self.ignored = @intCast(bits);
        self.ignored2 = @intCast(bits >> 2);
    }

    pub fn setCache(self : *@This(), level : anytype, cache : paging.PteCache) void {
        setPat(self, level,switch(cache) {
            .WRITE_BACK => .WRITE_BACK,
            .WRITE_COMBINING => .WRITE_COMBINING,
            .UNCACHED => .UNCACHEABLE,
        });
    }

    pub fn setWrite(self : *@This(), level : anytype, write : bool) void {
        _ = level;
        self.writable = write;
    }

    pub fn setRead(self : *@This(), level : anytype, read : bool) void {
        _ = self;
        _ = level;
        _ = read;
        return;
    }

    pub fn setExec(self : *@This(), level : anytype, exec : bool) void {
        _ = level;
        if(cpu.FEATURES.EXECUTE_BIT == false) return;

        self.no_execute = !exec;
    }

    pub fn setPresent(self : *@This(), level : anytype, present : bool) void {
        _ = level;
        self.present = present;
    }

    pub fn setUser(self : *@This(), level : anytype, user : bool) void {
        _ = level;
        self.user = user;
    }

    pub fn setPfe(self : *@This(), level : anytype, pfe : bool) void {
        if(level > cpu.FEATURES.MAX_PAGE_SIZE) return;

        if(level == 0) return;
        self.bits.pfe = pfe;
    }

    pub fn setEntry(self : *@This(), level : anytype, entry : mem.Paddr) void {
        const mask : u64 = mem.PHYS_ADDR_SIZE & (~bin.setBits((@as(u64, level) * paging.PTE_ENTRY_BITS * @as(u64, @intFromBool(self.getPfe(level)))) + paging.PTE_SIZE_BITS));
        self.* = @bitCast((@as(u64, @bitCast(self.*)) & ~mask) | (entry.val & mask));
    }

    pub fn setEmpty(self : *@This(), level : anytype) void {
        _ = level;
        self.* = @bitCast(@as(u64, 0));
    }

    pub fn setAccessed(self : *@This(), level : anytype, accessed : bool) void {
        _ = level;
        self.accessed = accessed;
    }

    pub fn setGlobal(self : *@This(), level : anytype, global : bool) void {
        debug.assert(self.getPfe(level));

        self.bits2.global = global;
    }

    pub fn setDirty(self : *@This(), level : anytype, dirty : bool) void {
        debug.assert(self.getPfe(level));

        self.dirty = dirty;
    }

    pub fn getNumOsBits() u8 {
        // This is the maximum number of consistent bits across all Pte types
        return 9;
    }

    pub fn getOsBits(self : @This()) u64 {
        var bits : u9 = 0;
        bits |= @intCast(self.ignored);
        bits |= @intCast(self.ignored2 << 2);

        return @intCast(bits);
    }

    pub fn getCache(self : *@This(), level : anytype) paging.PteCache {
        return switch(getPat(self, level)) {
            .WRITE_BACK => .WRITE_BACK,
            .WRITE_COMBINING => .WRITE_COMBINING,
            .UNCACHEABLE => .UNCACHED,
        };
    }

    pub fn getWrite(self : *@This(), level : anytype) bool {
        _ = level;
        return self.writable;
    }

    pub fn getRead(self : *@This(), level : anytype) bool {
        _ = self;
        _ = level;
        return true;
    }

    pub fn getExec(self : *@This(), level : anytype) bool {
        _ = level;
        if(cpu.FEATURES.EXECUTE_BIT == false) return true;

        return !self.no_execute;
    }

    pub fn getPresent(self : *@This(), level : anytype) bool {
        _ = level;
        return self.present;
    }

    pub fn getUser(self : *@This(), level : anytype) bool {
        _ = level;
        return self.user;
    }

    pub fn getPfe(self : *@This(), level : anytype) bool {
        if(level == 0) return true;
        return self.bits.pfe;
    }

    pub fn getEntry(self : *@This(), level : anytype) mem.Paddr {
        const mask : u64 = mem.PHYS_ADDR_SIZE & (~bin.setBits((level * paging.PTE_ENTRY_BITS * @as(u64, @intFromBool(self.getPfe(level)))) + paging.PTE_SIZE_BITS));
        return .{.val = @as(u64, @bitCast(self.*)) & mask,};
    }

    pub fn getEmpty(self : *@This(), level : anytype) bool {
        _ = level;
        return bin.isZero(self.*);
    }

    pub fn getAccessed(self : *@This(), level : anytype) bool {
        _ = level;
        return self.accessed;
    }

    pub fn getGlobal(self : *@This(), level : anytype) bool {
        debug.assert(self.getPfe(level));

        return self.global;
    }

    pub fn getDirty(self : *@This(), level : anytype) bool {
        debug.assert(self.getPfe(level));

        return self.dirty;
    }
};