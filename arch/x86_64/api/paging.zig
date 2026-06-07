const kernel = @import("kernel");
const paging = kernel.mm.paging;
const mem = kernel.mm.memory;
const bin = kernel.util.binary;
const debug = @import("std").debug;

const reg = @import("arch").reg;

const cpu = @import("cpu.zig");

pub fn set_page_tables(tables : *paging.Ptable) void {
    reg.set_cr3(@bitCast(mem.Vaddr.as_virt(@intFromPtr(tables)).to_phys().val));
}

pub fn get_page_tables() *paging.Ptable {
    return @ptrFromInt(mem.Paddr.as_phys(@bitCast(reg.get_cr3())).to_virt().val);
}

pub fn flush_tlb() void {
    reg.set_cr3(reg.get_cr3());
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

    fn set_pat(pte : *Pte, level : anytype, pat : reg.PatTypes) void {
        const bits = @intFromEnum(pat);
        pte.pwt = bin.get_bit(0, bits);
        pte.pcd = bin.get_bit(1, bits);

        if(level == 0) {
            pte.bits.pat = bin.get_bit(2, bits);
        }
        else
            pte.bits3.pat = bin.get_bit(2, bits);
    }

    fn get_pat(pte : *Pte, level : anytype) reg.PatTypes {
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

    pub fn set_os_bits(self : *@This(), bits : u64) void {
        self.ignored = @intCast(bits);
        self.ignored2 = @intCast(bits >> 2);
    }

    pub fn set_cache(self : *@This(), level : anytype, cache : paging.PteCache) void {
        set_pat(self, level,switch(cache) {
            paging.PteCache.WRITE_BACK => reg.PatTypes.WRITE_BACK,
            paging.PteCache.WRITE_COMBINING => reg.PatTypes.WRITE_COMBINING,
            paging.PteCache.UNCACHED => reg.PatTypes.UNCACHEABLE,
        });
    }

    pub fn set_write(self : *@This(), level : anytype, write : bool) void {
        _ = level;
        self.writable = write;
    }

    pub fn set_read(self : *@This(), level : anytype, read : bool) void {
        _ = self;
        _ = level;
        _ = read;
        return;
    }

    pub fn set_exec(self : *@This(), level : anytype, exec : bool) void {
        _ = level;
        if(cpu.FEATURES.EXECUTE_BIT == false) return;

        self.no_execute = !exec;
    }

    pub fn set_present(self : *@This(), level : anytype, present : bool) void {
        _ = level;
        self.present = present;
    }

    pub fn set_user(self : *@This(), level : anytype, user : bool) void {
        _ = level;
        self.user = user;
    }

    pub fn set_pfe(self : *@This(), level : anytype, pfe : bool) void {
        if(level > cpu.FEATURES.MAX_PAGE_SIZE) return;

        if(level == 0) return;
        self.bits.pfe = pfe;
    }

    pub fn set_entry(self : *@This(), level : anytype, entry : mem.Paddr) void {
        const mask : u64 = mem.PHYS_ADDR_SIZE & (~bin.set_bits((level * paging.PTE_ENTRY_BITS * @as(u64, @intFromBool(self.get_pfe(level)))) + paging.PTE_SIZE_BITS));
        self.* = @bitCast((@as(u64, @bitCast(self.*)) & ~mask) | (entry.val & mask));
    }

    pub fn set_empty(self : *@This(), level : anytype) void {
        _ = level;
        self.* = @bitCast(@as(u64, 0));
    }

    pub fn set_accessed(self : *@This(), level : anytype, accessed : bool) void {
        _ = level;
        self.accessed = accessed;
    }

    pub fn set_global(self : *@This(), level : anytype, global : bool) void {
        debug.assert(self.get_pfe(level));

        self.bits2.global = global;
    }

    pub fn set_dirty(self : *@This(), level : anytype, dirty : bool) void {
        debug.assert(self.get_pfe(level));

        self.dirty = dirty;
    }

    pub fn get_num_os_bits() u8 {
        // This is the maximum number of consistent bits across all Pte types
        return 9;
    }

    pub fn get_os_bits(self : @This()) u64 {
        var bits : u9 = 0;
        bits |= @intCast(self.ignored);
        bits |= @intCast(self.ignored2 << 2);

        return @intCast(bits);
    }

    pub fn get_cache(self : *@This(), level : anytype) paging.PteCache {
        return switch(get_pat(self, level)) {
            reg.PatTypes.WRITE_BACK => paging.PteCache.WRITE_BACK,
            reg.PatTypes.WRITE_COMBINING => paging.PteCache.WRITE_COMBINING,
            reg.PatTypes.UNCACHEABLE => paging.PteCache.UNCACHED,
        };
    }

    pub fn get_write(self : *@This(), level : anytype) bool {
        _ = level;
        return self.writable;
    }

    pub fn get_read(self : *@This(), level : anytype) bool {
        _ = self;
        _ = level;
        return true;
    }

    pub fn get_exec(self : *@This(), level : anytype) bool {
        _ = level;
        if(cpu.FEATURES.EXECUTE_BIT == false) return true;

        return !self.no_execute;
    }

    pub fn get_present(self : *@This(), level : anytype) bool {
        _ = level;
        return self.present;
    }

    pub fn get_user(self : *@This(), level : anytype) bool {
        _ = level;
        return self.user;
    }

    pub fn get_pfe(self : *@This(), level : anytype) bool {
        if(level == 0) return true;
        return self.bits.pfe;
    }

    pub fn get_entry(self : *@This(), level : anytype) mem.Paddr {
        const mask : u64 = mem.PHYS_ADDR_SIZE & (~bin.set_bits((level * paging.PTE_ENTRY_BITS * @as(u64, @intFromBool(self.get_pfe(level)))) + paging.PTE_SIZE_BITS));
        return .{.val = @as(u64, @bitCast(self.*)) & mask,};
    }

    pub fn get_empty(self : *@This(), level : anytype) bool {
        _ = level;
        return @as(u64, @bitCast(self.*)) == 0;
    }

    pub fn get_accessed(self : *@This(), level : anytype) bool {
        _ = level;
        return self.accessed;
    }

    pub fn get_global(self : *@This(), level : anytype) bool {
        debug.assert(self.get_pfe(level));

        return self.global;
    }

    pub fn get_dirty(self : *@This(), level : anytype) bool {
        debug.assert(self.get_pfe(level));

        return self.dirty;
    }
};