const fmt = @import("std").fmt;
const kernel = @import("kernel");
const bin = kernel.util.binary;
const types = kernel.util.types;
const limine = @import("lib").limine;
const memmap_type = limine.LIMINE_MEMMAP_TYPE;

const mm = @import("memory.zig");

const log = @import("kernel").util.log;
const print = log.print;
const panic = log.panic;

fn overlap_priority(memtype : memmap_type) u8 {
    return switch(memtype) {
        memmap_type.USABLE => 0,
        memmap_type.BOOTLOADER_RECLAIMABLE => 1,
        memmap_type.ACPI_RECLAIMABLE => 2,
        memmap_type.ACPI_NVS => 3,
        memmap_type.EXECUTABLE_AND_MODULES => 4,
        memmap_type.FRAMEBUFFER => 5,
        memmap_type.RESERVED => 6,
        memmap_type.BAD_MEMORY => 7,
        else => 8
    };
}

fn memtype_to_string(memtype : memmap_type) []const u8 {
    return switch (memtype) {
        memmap_type.USABLE => "Usable",
        memmap_type.BOOTLOADER_RECLAIMABLE => "Bootloader Reclaimable",
        memmap_type.ACPI_RECLAIMABLE => "ACPI Reclaimable",
        memmap_type.ACPI_NVS => "APCI NVS",
        memmap_type.EXECUTABLE_AND_MODULES => "Executable/Modules",
        memmap_type.RESERVED => "Reserved",
        memmap_type.BAD_MEMORY => "Bad Memory",
        memmap_type.FRAMEBUFFER => "Framebuffer",
        else => "Unknown"
    };
}

fn sanitize_memmap() u64 {
    print("  Limine Memory Map:\n", .{});
    print("  {s:<18} {s:<18} {s:<8} Type\n  ", .{"Start", "End", "Size"});
    log.print_char('-', 60);
    print("\n", .{});

    for(0..kernel.mmap_request.response.*.entry_count) |i| {
        const entry : *limine.limine_memmap_entry = &kernel.mmap_request.response.*.entries[i].*;

        print("  0x{X:<18} 0x{X:<18} ", .{entry.base, entry.base + entry.length});
        log.print_size(entry.length, 10);
        print(" {s:<8}\n", .{memtype_to_string(@enumFromInt(entry.type))});
    }

    var num_usable : u64 = 0;

    // Align region bounds to 4KB page sizes
    for(0..kernel.mmap_request.response.*.entry_count) |i| {
        const entry : *limine.limine_memmap_entry = &kernel.mmap_request.response.*.entries[i].*;

        entry.base = bin.align_down(entry.base, types.SIZE_4KB);
        entry.length = bin.align_up(entry.length, types.SIZE_4KB);

        const memtype : memmap_type = @enumFromInt(entry.type);
        if(memtype == memmap_type.USABLE) {
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
        const entry : *limine.limine_memmap_entry = &kernel.mmap_request.response.*.entries[i].*;
        if(entry.length == 0) continue;
        const next_entry : *limine.limine_memmap_entry = &kernel.mmap_request.response.*.entries[i+1].*;

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
        const entry : *limine.limine_memmap_entry = &kernel.mmap_request.response.*.entries[i].*;
        if(entry.length == 0)
            continue;

        print("  0x{X:<18} 0x{X:<18} ", .{entry.base, entry.base + entry.length});
        log.print_size(entry.length, 10);
        print(" {s:<8}\n", .{memtype_to_string(@enumFromInt(entry.type))});
    }

    return num_usable;
}

pub fn setup_phys_mem_mgmt() void {
    print("\nmm: Setting up Physical Memory Management\n", .{});

    mm.PAGE_OFFSET.val = kernel.hhdm_request.response.*.offset;
    if(mm.PAGE_OFFSET.val != mm.KERNEL_MEMORY.val) {
        panic("mm: Limine specified a different PAGE_OFFSET than expected! {} vs {}\n", .{mm.PAGE_OFFSET.val, mm.KERNEL_MEMORY.val});
    }

    const num_usable : u64 = sanitize_memmap();
}