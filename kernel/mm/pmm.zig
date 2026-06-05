const std = @import("std");

const kernel = @import("kernel");
const config = kernel.config;
const bin = kernel.util.binary;
const types = kernel.util.types;
const lib = @import("lib");
const elf = lib.elf;
const limine = lib.limine;
const MmapType = limine.LIMINE_MEMMAP_TYPE;
const process = kernel.pm.process;
var kernel_root_pt = process.kernel_process.addr_space.root_pt;

const memory = @import("memory.zig");
const vmm = @import("vmm.zig");
const paging = @import("paging.zig");

const log = @import("kernel").util.log;
const print = log.print;
const panic = log.panic;

var usable_array : [config.MAX_MEMORY_REGIONS]CachedMmapEntry = undefined;
var USABLE : []CachedMmapEntry = undefined;

fn overlap_priority(memtype : MmapType) u8 {
    return switch(memtype) {
        MmapType.USABLE => 0,
        MmapType.BOOTLOADER_RECLAIMABLE => 1,
        MmapType.ACPI_RECLAIMABLE => 2,
        MmapType.ACPI_NVS => 3,
        MmapType.EXECUTABLE_AND_MODULES => 4,
        MmapType.FRAMEBUFFER => 5,
        MmapType.RESERVED => 6,
        MmapType.BAD_MEMORY => 7,
        else => 8
    };
}

fn memtype_to_string(memtype : MmapType) []const u8 {
    return switch (memtype) {
        MmapType.USABLE => "Usable",
        MmapType.BOOTLOADER_RECLAIMABLE => "Bootloader Reclaimable",
        MmapType.ACPI_RECLAIMABLE => "ACPI Reclaimable",
        MmapType.ACPI_NVS => "APCI NVS",
        MmapType.EXECUTABLE_AND_MODULES => "Executable/Modules",
        MmapType.RESERVED => "Reserved",
        MmapType.BAD_MEMORY => "Bad Memory",
        MmapType.FRAMEBUFFER => "Framebuffer",
        else => "Unknown"
    };
}

pub const CachedMmapEntry = struct {
    region_start : u64,
    region_end : u64,
    block_start : u64,  // Cache of the start block size
    block_end : u64     // Cache of the end block size
};

fn sanitize_mmap() u64 {
    print("  Limine Memory Map:\n", .{});
    print("  {s:<18} {s:<18} {s:<8} Type\n  ", .{"Start", "End", "Size"});
    log.print_char('-', 60);
    print("\n", .{});

    for(0..kernel.mmap_request.response.*.entry_count) |i| {
        const entry = &kernel.mmap_request.response.*.entries[i].*;

        print("  0x{X:<18} 0x{X:<18} ", .{entry.base, entry.base + entry.length});
        log.print_size(entry.length, 10);
        print(" {s:<8}\n", .{memtype_to_string(@enumFromInt(entry.type))});
    }

    var num_usable : u64 = 0;

    // Align region bounds to 4KB page sizes
    for(0..kernel.mmap_request.response.*.entry_count) |i| {
        const entry = &kernel.mmap_request.response.*.entries[i].*;

        entry.base = bin.align_down(entry.base, types.SIZE_4KB);
        entry.length = bin.align_up(entry.length, types.SIZE_4KB);

        const memtype : MmapType = @enumFromInt(entry.type);
        if(memtype == MmapType.USABLE) {
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
    for(0..(kernel.mmap_request.response.*.entry_count - 1)) |i| {
        const entry = &kernel.mmap_request.response.*.entries[i].*;
        if(entry.length == 0) continue;
        const next_entry = &kernel.mmap_request.response.*.entries[i+1].*;

        if (entry.base + entry.length > next_entry.base) {
            // First has higher priority, move next up
            if (overlap_priority(@enumFromInt(entry.type)) > overlap_priority(@enumFromInt(next_entry.type))) {
                const new_base : u64 = entry.base + entry.length;
                next_entry.length -= new_base - next_entry.base;
                next_entry.base = new_base;
            }
            // Next has higher priority, move first down
            else
                entry.length = next_entry.base - entry.base;
        }
    }

    print("\n  Sanitized Memory Map:\n", .{});
    print("  {s:<18} {s:<18} {s:<8} Type\n  ", .{"Start", "End", "Size"});
    log.print_char('-', 60);
    print("\n", .{});

    for(0..kernel.mmap_request.response.*.entry_count) |i| {
        const entry = &kernel.mmap_request.response.*.entries[i].*;
        if(entry.length == 0)
            continue;

        print("  0x{X:<18} 0x{X:<18} ", .{entry.base, entry.base + entry.length});
        log.print_size(entry.length, 10);
        print(" {s:<8}\n", .{memtype_to_string(@enumFromInt(entry.type))});
    }

    return num_usable;
}

fn populate_usable() void {
    var usable_index : u64 = 0;

    for(0..kernel.mmap_request.response.*.entry_count) |i| {
        const entry = &kernel.mmap_request.response.*.entries[i].*;
        const memtype : MmapType = @enumFromInt(entry.type);

        if (memtype != MmapType.USABLE) continue;

        USABLE[usable_index].block_start = 0;
        USABLE[usable_index].block_end = 0;
        USABLE[usable_index].region_start = entry.base;
        USABLE[usable_index].region_end = entry.base + entry.length;

        usable_index += 1;
    }
}

pub fn alloc_boot_page() memory.Paddr {
    var selected : ?*CachedMmapEntry = null;
    var end : bool = false;
    var min_order : u64 = std.math.maxInt(u64);

    for (0..USABLE.len) |i| {
        const entry : *CachedMmapEntry = &USABLE[i];
        var alignment : u64 = undefined;

        if (entry.region_start == entry.region_end) continue;

        alignment = entry.block_start;
        if(alignment == 0) {
            alignment = bin.max_align_between(entry.region_start, entry.region_end);
        }

        if (min_order > alignment) {
            min_order = alignment;
            selected = entry;
            end = false;
        }

        alignment = entry.block_end;
        if(alignment == 0) {
            alignment = bin.max_align_between(entry.region_end, entry.region_start);
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

fn map_page_mdata(root_pt : *paging.Ptable) void {
    var pframe : paging.Pte = paging.PFE_DEFAULTS[0];
    pframe.set_global(0, true);

    var mem_size : u64 = 0;
    var metadata_size : u64 = 0;

    for(0..kernel.mmap_request.response.*.entry_count) |i| {
        const entry = &kernel.mmap_request.response.*.entries[i].*;
        const memtype : MmapType = @enumFromInt(entry.type);

        if (memtype != MmapType.USABLE) continue;

        const page_start : u64 = memory.PAGE_METADATA.val + bin.align_down((entry.base / types.SIZE_4KB) * @sizeOf(paging.PageInfo), types.SIZE_4KB);
        const page_end : u64 = memory.PAGE_METADATA.val + bin.align_up(((entry.base + entry.length) / types.SIZE_4KB) * @sizeOf(paging.PageInfo), types.SIZE_4KB);

        mem_size += bin.align_up(entry.length, types.SIZE_4KB);
        metadata_size += page_end - page_start;

        var page : u64 = page_start;
        while (page < page_end) : (page += types.SIZE_4KB) {
            pframe.set_entry(0, alloc_boot_page());
            paging.map_boot_page(page, pframe, 0, root_pt);
        }
    }

    print("    Available memory ", .{});
    log.print_size(mem_size, 0);
    print("\n    Page metadata overhead ", .{});
    log.print_size(metadata_size, 0);
    print("\n", .{});
}

fn map_new_hhdm(root_pt : *paging.Ptable) void {
    _ = root_pt;
}

fn map_kernel_image(root_pt : *paging.Ptable) void {
    log.apanic(kernel.executable_address_request.response.*.virtual_base != memory.KERNEL_IMAGE.val,
        "mm: Limine kernel base doesn't match the expected base!\n", .{});

    const elf_hdr : *elf.ElfHdr = @ptrCast(@alignCast(kernel.executable_file_request.response.*.executable_file.address));
    log.apanic(!std.mem.eql(u8, &elf_hdr.id.magic, std.elf.MAGIC), "mm: Kernel ELF file wasn't found! Cannot remap kernel image!\n", .{});
    for(0..elf_hdr.ph_num) |i| {
        const phdr : *elf.ElfPrgHdr = @ptrFromInt(@intFromPtr(elf_hdr) + elf_hdr.ph_off + elf_hdr.ph_ent_size * i);
        if(phdr.type != elf.ElfPrgHdr.PT.LOAD) continue;

        var pfe : paging.Pte = paging.PFE_DEFAULTS[0];
        pfe.set_global(0, true);
        pfe.set_exec(0, phdr.flags.execute);
        pfe.set_write(0, phdr.flags.write);
        pfe.set_read(0, phdr.flags.read);

        const start : u64 = phdr.vaddr;
        const size : u64 = phdr.mem_sz;

        const pstart : u64 = kernel.executable_address_request.response.*.physical_base + start - memory.KERNEL_IMAGE.val;

        var addr : u64 = 0;
        while(addr < size) : (addr += types.SIZE_4KB) {
            pfe.set_entry(0, .{.val = pstart + addr});
            paging.map_boot_page(start + addr, pfe, 0, root_pt);
        }
    }
}

fn map_modules(root_pt : *paging.Ptable) void {
    _ = root_pt;
}

fn map_page_cache(root_pt : *paging.Ptable) void {
    _ = root_pt;
}

fn switch_to_new_ptables() void {
    // Setup paging information
    paging.setup_paging();

    // The new kernel root page table
    kernel_root_pt = @ptrFromInt(alloc_boot_page().to_virt().val);
    memory.memset(kernel_root_pt, types.SIZE_4KB, 0);

    // Setup page metadata
    print("  Mapping Page Metadata:\n", .{});
    map_page_mdata(kernel_root_pt);

    // Setup the Higher-Half Direct Map for applicable regions
    print("  Mapping HHDM\n", .{});
    map_new_hhdm(kernel_root_pt);

    // Setup mappings for kernel sections
    print("  Mapping Kernel Image\n", .{});
    map_kernel_image(kernel_root_pt);

    // Setup mappings for modules
    print("  Mapping Kernel Modules\n", .{});
    map_modules(kernel_root_pt);

    // Setup page caches in the per-cpu storage region
    print("  Mapping per-cpu Page Cache\n", .{});
    map_page_cache(kernel_root_pt);

    // Switch to the new page tables
    print("  Switching to new Page Tables\n", .{});
}

pub fn setup_phys_mem_mgmt() void {
    print("\nmm: Setting up Physical Memory Management\n", .{});

    memory.PAGE_OFFSET.val = kernel.hhdm_request.response.*.offset;
    if(memory.PAGE_OFFSET.val != memory.KERNEL_MEMORY.val) {
        panic("mm: Limine specified a different PAGE_OFFSET than expected! {} vs {}\n", .{memory.PAGE_OFFSET.val, memory.KERNEL_MEMORY.val});
    }

    const num_usable : u64 = sanitize_mmap();

    log.apanic(num_usable > config.MAX_MEMORY_REGIONS, "mm: More memory regions than we can handle!\n", .{});
    USABLE = usable_array[0..num_usable];

    print("\nmm: Setting up boot page allocator data\n", .{});
    populate_usable();

    print("\nmm: Setting up new page tables:\n", .{});
    switch_to_new_ptables();
}