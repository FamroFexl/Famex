const std = @import("std");

const kernel = @import("kernel");
const cast = kernel.cast;
const config = kernel.config;
const bin = kernel.util.binary;
const types = kernel.util.types;
const lib = @import("lib");
const elf = lib.elf;
const limine = lib.limine;
const process = kernel.pm.process;

const memory = @import("memory.zig");
const vmm = @import("vmm.zig");
const paging = @import("paging.zig");
const buddyAlloc = @import("buddyAlloc.zig");
const slubAlloc = @import("slubAlloc.zig");
const Addr = memory.Addr;

const arch = @import("arch");
const cpu = arch.cpu;

const log = @import("kernel").util.log;
const print = log.print;
const panic = log.panic;

var usable_array : [config.MAX_MEMORY_REGIONS]CachedMmapEntry = undefined;
pub var USABLE : []CachedMmapEntry = undefined;

fn overlapPriority(memtype : limine.LimineMemmapEntry.MemType) u8 {
    return switch(memtype) {
        .USABLE => 0,
        .BOOTLOADER_RECLAIMABLE => 1,
        .ACPI_RECLAIMABLE => 2,
        .ACPI_NVS => 3,
        .EXECUTABLE_AND_MODULES => 4,
        .FRAMEBUFFER => 5,
        .RESERVED => 6,
        .BAD_MEMORY => 7,
        else => 8
    };
}

fn memtypeToString(memtype : limine.LimineMemmapEntry.MemType) []const u8 {
    return switch (memtype) {
        .USABLE => "Usable",
        .BOOTLOADER_RECLAIMABLE => "Bootloader Reclaimable",
        .ACPI_RECLAIMABLE => "ACPI Reclaimable",
        .ACPI_NVS => "APCI NVS",
        .EXECUTABLE_AND_MODULES => "Executable/Modules",
        .RESERVED => "Reserved",
        .BAD_MEMORY => "Bad Memory",
        .FRAMEBUFFER => "Framebuffer",
        else => "Unknown"
    };
}

fn pageLevelToSize(level : anytype) usize {
    return switch (level) {
        0 => types.SIZE_4KB,
        1 => types.SIZE_2MB,
        2 => types.SIZE_1GB,
        else => types.SIZE_4KB,
    };
}

pub const CachedMmapEntry = struct {
    region_start : u64,
    region_end : u64,
    block_start : u64,  // Cache of the start block size
    block_end : u64     // Cache of the end block size
};

fn sanitizeMmap() u64 {
    //print("  Limine Memory Map:\n", .{});
    //print("  {s:<18} {s:<18} {s:<8} Type\n  ", .{"Start", "End", "Size"});
    //log.printChar('-', 60);
    //print("\n", .{});

    // for(0..kernel.Limine.mmap_request.response.*.entry_count) |i| {
        // const entry = &kernel.Limine.mmap_request.response.*.entries[i].*;

        // print("  0x{X:<18} 0x{X:<18} ", .{entry.base, entry.base + entry.length});
        // log.printSize(entry.length, 10);
        // print(" {s:<8}\n", .{memtypeToString(entry.type)});
    // }

    var num_usable : u64 = 0;

    // Align region bounds to 4KB page sizes
    for(0..kernel.Limine.mmap_request.response.*.entry_count) |i| {
        const entry = &kernel.Limine.mmap_request.response.*.entries[i].*;

        entry.base = bin.alignDown(entry.base, types.SIZE_4KB);
        entry.length = bin.alignUp(entry.length, types.SIZE_4KB);

        if(entry.type == .USABLE) {
            // We do not like page 0 in physical memory
            if(entry.base == 0) {
                entry.base += types.SIZE_4KB;
                entry.length -= types.SIZE_4KB;
            }

            if(entry.length == 0)
                continue;

            num_usable += 1;
        }
    }

    // Remove region overlaps using overlap_priority
    for(0..(kernel.Limine.mmap_request.response.*.entry_count - 1)) |i| {
        const entry = &kernel.Limine.mmap_request.response.*.entries[i].*;
        if(entry.length == 0) continue;
        const next_entry = &kernel.Limine.mmap_request.response.*.entries[i+1].*;

        if (entry.base + entry.length > next_entry.base) {
            // First has higher priority, move next up
            if (overlapPriority(entry.type) > overlapPriority(next_entry.type)) {
                const new_base : u64 = entry.base + entry.length;
                next_entry.length -= new_base - next_entry.base;
                next_entry.base = new_base;
            }
            // Next has higher priority, move first down
            else
                entry.length = next_entry.base - entry.base;
        }
    }

    print("  Sanitized Memory Map:\n", .{});
    print("  {s:<18} {s:<18} {s:<10} Type\n  ", .{"Start", "End", "Size"});
    log.printChar('-', 60);
    print("\n", .{});

    for (0..kernel.Limine.mmap_request.response.*.entry_count) |i| {
        const entry = &kernel.Limine.mmap_request.response.*.entries[i].*;
        if(entry.length == 0)
            continue;

        print("  0x{X:<16} 0x{X:<16} ", .{entry.base, entry.base + entry.length});
        log.printSize(entry.length, 10);
        print(" {s:<8}\n", .{memtypeToString(entry.type)});
    }

    return num_usable;
}

fn populateUsable() void {
    var usable_index : u64 = 0;

    for(0..kernel.Limine.mmap_request.response.*.entry_count) |i| {
        const entry = &kernel.Limine.mmap_request.response.*.entries[i].*;

        if (entry.type != .USABLE) continue;

        USABLE[usable_index].block_start = 0;
        USABLE[usable_index].block_end = 0;
        USABLE[usable_index].region_start = entry.base;
        USABLE[usable_index].region_end = entry.base + entry.length;

        usable_index += 1;
    }
}

pub fn allocBootPage() memory.Paddr {
    var selected : ?*CachedMmapEntry = null;
    var end : bool = false;
    var min_order : u64 = std.math.maxInt(u64);

    for (0..USABLE.len) |i| {
        const entry : *CachedMmapEntry = &USABLE[i];
        var alignment : u64 = undefined;

        if (entry.region_start == entry.region_end) continue;

        alignment = entry.block_start;
        if(alignment == 0) {
            alignment = bin.maxAlignBetween(entry.region_start, entry.region_end);
        }

        if (min_order > alignment) {
            min_order = alignment;
            selected = entry;
            end = false;
        }

        alignment = entry.block_end;
        if(alignment == 0) {
            alignment = bin.maxAlignBetween(entry.region_end, entry.region_start);
        }

        if (min_order > alignment) {
            min_order = alignment;
            selected = entry;
            end = true;
        }

        if (min_order == types.SIZE_4KB) break;
    }

    log.apanic(selected == null, "Boot allocator failed! Not enough memory available!", .{});

    if (end) {
        selected.?.block_end = 0;
        selected.?.region_end -= types.SIZE_4KB;
        return .{.val = selected.?.region_end};
    }

    selected.?.block_start = 0;
    selected.?.region_start += types.SIZE_4KB;

    return .{.val = selected.?.region_start - types.SIZE_4KB};
}

fn mapPageMdata(kernel_root_pt : *paging.Ptable) void {
    print("  Mapping Page Metadata:\n", .{});

    var pframe : paging.Pte = paging.PFE_DEFAULTS[0];
    pframe.setGlobal(0, true);

    var mem_size : u64 = 0;
    var metadata_size : u64 = 0;

    for(0..kernel.Limine.mmap_request.response.*.entry_count) |i| {
        const entry = &kernel.Limine.mmap_request.response.*.entries[i].*;

        if (entry.type != .USABLE) continue;

        const page_start : u64 = memory.PAGE_METADATA.val + bin.alignDown((entry.base / types.SIZE_4KB) * @sizeOf(paging.PageInfo), types.SIZE_4KB);
        const page_end : u64 = memory.PAGE_METADATA.val + bin.alignUp(((entry.base + entry.length) / types.SIZE_4KB) * @sizeOf(paging.PageInfo), types.SIZE_4KB);

        mem_size += bin.alignUp(entry.length, types.SIZE_4KB);
        metadata_size += page_end - page_start;

        var page : u64 = page_start;
        while (page < page_end) : (page += types.SIZE_4KB) {
            pframe.setEntry(0, allocBootPage());
            paging.mapBootPage(memory.Vaddr.asVirt(page), pframe, 0, kernel_root_pt);
        }
    }

    print("    Available memory ", .{});
    log.printSize(mem_size, 0);
    print("\n    Page metadata overhead ", .{});
    log.printSize(metadata_size, 0);
    print("\n", .{});
}

/// Higher Half Direct Map of all memory, excluding reserved and bad regions
fn mapNewHhdm(kernel_root_pt : *paging.Ptable) void {
    print("  Mapping HHDM\n", .{});

    var pframes : [paging.PFE_MAX_DEPTH]paging.Pte = undefined;
    @memcpy(pframes[0..cpu.FEATURES.MAX_PAGE_SIZE + 1], paging.PFE_DEFAULTS[0..cpu.FEATURES.MAX_PAGE_SIZE + 1]);

    for (&pframes, 0..) |*pte, i| {
        pte.setGlobal(i, true);
    }

    outer: for(0..kernel.Limine.mmap_request.response.*.entry_count) |i| {
        const entry = &kernel.Limine.mmap_request.response.*.entries[i].*;
        if (entry.length == 0) continue;

        switch (entry.type) {
            .BAD_MEMORY, .RESERVED, .EXECUTABLE_AND_MODULES => continue :outer,
            else => {},
        }

        const cache : paging.PteCache = switch (entry.type) {
            .ACPI_NVS => paging.PteCache.UNCACHED,
            .FRAMEBUFFER => paging.PteCache.WRITE_COMBINING,
            else => paging.PteCache.WRITE_BACK,
        };

        for (&pframes, 0..) |*pte, j|
            pte.setCache(j, cache);

        const end : memory.Paddr = .{.val = entry.base + entry.length};
        var cur_addr : memory.Paddr = .{.val = entry.base};

        while (cur_addr.val < end.val) {
            var cur_level = cpu.FEATURES.MAX_PAGE_SIZE;
            var page_size = pageLevelToSize(cur_level);

            while (bin.alignDown(cur_addr.val, page_size) != cur_addr.val or cur_addr.val + page_size > end.val) {
                cur_level -= 1;
                page_size = pageLevelToSize(cur_level);
            }

            pframes[cur_level].setEntry(cur_level, cur_addr);
            paging.mapBootPage(.{.val = memory.KERNEL_MEMORY.val + cur_addr.val}, pframes[cur_level], cur_level, kernel_root_pt);

            cur_addr.val += page_size;
        }
    }
}

fn mapKernelImage(kernel_root_pt : *paging.Ptable) void {
    print("  Mapping Kernel Image\n", .{});

    log.apanic(kernel.Limine.executable_address_request.response.*.virtual_base != memory.KERNEL_IMAGE.val,
        "mm: Limine kernel base doesn't match the expected base!\n", .{});

    const elf_hdr = cast.toPtr(*elf.ElfHdr, kernel.Limine.executable_file_request.response.*.executable_file.address);
    log.apanic(!elf_hdr.isElf(), "mm: Kernel ELF file wasn't found! Cannot remap kernel image!\n", .{});
    for(0..elf_hdr.ph_num) |i| {
        const phdr = elf_hdr.getPhdrByIndex(i).?;
        if(phdr.type != .LOAD) continue;

        var pfe : paging.Pte = paging.PFE_DEFAULTS[0];
        pfe.setGlobal(0, true);
        pfe.setExec(0, phdr.flags.execute);
        pfe.setWrite(0, phdr.flags.write);
        pfe.setRead(0, phdr.flags.read);

        const start : memory.Vaddr = .{.val = phdr.vaddr};
        const size : usize = phdr.mem_sz;

        const pstart : u64 = kernel.Limine.executable_address_request.response.*.physical_base + start.val - memory.KERNEL_IMAGE.val;

        var addr : u64 = 0;
        while(addr < size) : (addr += types.SIZE_4KB) {
            pfe.setEntry(0, .{.val = pstart + addr});
            paging.mapBootPage(.{.val = start.val + addr}, pfe, 0, kernel_root_pt);
        }
    }
}

fn mapPercpu(kernel_root_pt : *paging.Ptable) void {
    print("  Mapping per-cpu static region\n", .{});

    const elf_hdr = cast.toPtr(*elf.ElfHdr, kernel.Limine.executable_file_request.response.*.executable_file.address);
    const shdr = elf_hdr.getShdrByName(".percpu") orelse @panic("Couldn't receive the static percpu section!");
    const size = bin.alignUp(shdr.size, types.SIZE_4KB);

    process.perCpu.PER_CPU_LINKER_OFFSET = .{.val = shdr.addr};
    process.perCpu.PER_CPU_STARTING_OFFSET = .{.val = size};

    var pfe : paging.Pte = paging.PFE_DEFAULTS[0];
    pfe.setGlobal(0, true);

    for (0..cpu.FEATURES.NUM_CPU_CORES) |j| {
        const vaddr_start = memory.PER_CPU_DATA.val + memory.PER_CPU_DATA_SIZE * j;
        var cur : u64 = 0;
        while (cur < size) : (cur += types.SIZE_4KB) {
            pfe.setEntry(0, allocBootPage());
            paging.mapBootPage(.{.val = vaddr_start + cur}, pfe, 0, kernel_root_pt);
        }
    }
}

fn mapPercpuDyn() void {
    print("  Mapping per-cpu dynamic region\n", .{});

    // This gives us 2MB per cpu of potential dynamic allocations
    const num_bits = types.SIZE_2MB / process.perCpu.PER_CPU_DYN_ALLOC_BYTES;
    const size = bin.toBytes(num_bits);
    const addr = memory.pmallocBytes(size);
    memory.memset(addr, size, 0);
    process.perCpu.dyn_alloc_bmap.init(addr, num_bits);
    process.perCpu.dyn_alloc_bmap_lock.init();
}

fn mapModules() void {
    print("  Mapping Kernel Modules\n", .{});

    if (kernel.Limine.module_request.response == null) return;

    var pfeDef : paging.Pte = paging.PFE_DEFAULTS[0];
    pfeDef.setGlobal(0, true);

    for(0..kernel.Limine.module_request.response.?.module_count) |i| {
        const module = &kernel.Limine.module_request.response.?.modules[i].*;
        const moduleAddr = memory.Paddr.asPhys(@intFromPtr(kernel.Limine.toPhys(module.address))).toVirt();
        // TODO something is wrong with pteNext or pteInit that causes it to skip the last page (if end is 0x7000->0x7fff, only up to 0x6000 will be mapped)
        const moduleSize = bin.alignUp(module.size, types.SIZE_4KB) + types.SIZE_4KB;

        const vaddr : memory.Vaddr = memory.Vaddr.asVirt(bin.alignDown(moduleAddr.val, types.SIZE_4KB));

        var state = kernel.PfeState(.MAP).create(&kernel.kernelProcess.addrSpace, vaddr, .asVirt(vaddr.val + moduleSize), .LEVEL_4KB);

        var curAddr = vaddr.toPhys();
        while (state.next()) |pfe| {
            // Skip over already mapped pages
            if (pfe.getEmpty(0) == false) continue;
            pfe.* = pfeDef;
            pfe.setEntry(0, curAddr);
            curAddr.val += types.SIZE_4KB;
        }
    }
}

fn switchToNewPtables() void {
    // Setup paging information
    paging.setup();

    const kernel_root_pt = &process.kernelProcess.addrSpace.rootPt;

    // The new kernel root page table
    kernel_root_pt.* = @ptrFromInt(allocBootPage().toVirt().val);
    memory.memset(kernel_root_pt.*, types.SIZE_4KB, 0);

    // Setup page metadata
    mapPageMdata(kernel_root_pt.*);


    // Setup the Higher-Half Direct Map for applicable regions
    mapNewHhdm(kernel_root_pt.*);

    // Setup mappings for kernel sections
    mapKernelImage(kernel_root_pt.*);

    // Setup page caches in the per-cpu storage region
    mapPercpu(kernel_root_pt.*);

    // Switch to the new page tables
    print("  Switching to new Page Tables\n", .{});
    _ = kernel_root_pt.*.switchTo();
}

pub fn setup() void {
    print("\nmm: Setting up Physical Memory Management\n", .{});

    memory.PAGE_OFFSET.val = kernel.Limine.hhdm_request.response.*.offset;
    if(memory.PAGE_OFFSET.val != memory.KERNEL_MEMORY.val) {
        panic("mm: Limine specified a different PAGE_OFFSET than expected! {} vs {}\n", .{memory.PAGE_OFFSET, memory.KERNEL_MEMORY});
    }

    const num_usable : u64 = sanitizeMmap();

    log.apanic(num_usable > config.MAX_MEMORY_REGIONS, "mm: More memory regions than we can handle!\n", .{});
    USABLE = usable_array[0..num_usable];

    print("\nmm: Setting up boot page allocator data\n", .{});
    populateUsable();

    print("\nmm: Setting up new page tables:\n", .{});
    switchToNewPtables();

    // We don't want irqs enabling before they should
    for (0..cpu.FEATURES.NUM_CPU_CORES) |i| {
        kernel.io.irq.irqSaveDepth.getGlobal(i).* = 1;
    }

    // Temporary way to set the cpu data of the bootstrap processor
    for (0..kernel.Limine.smp_request.response.x86.cpu_count) |i| {
        const smp_info : limine.LimineMpInfoX86 = kernel.Limine.smp_request.response.x86.cpus.x86[i].*;
        if (smp_info.lapic_id == kernel.Limine.smp_request.response.x86.bsp_lapic_id) {
            arch.cpu.setPerCpu(@ptrFromInt(memory.PER_CPU_DATA.val + memory.PER_CPU_DATA_SIZE * i));
        }
    }

    kernel.util.locks.setup();

    buddyAlloc.setup();

    mapPercpuDyn();

    slubAlloc.setup();

    mapModules();
}