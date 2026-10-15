const std = @import("std");

const kernel = @import("kernel");

pub const Header = struct {
    magic       : [6]u8,
    ino         : [8]u8,
    mode        : [8]u8,
    uid         : [8]u8,
    gid         : [8]u8,
    nlink       : [8]u8,
    mtime       : [8]u8,
    filesize    : [8]u8,
    devmajor    : [8]u8,
    devminor    : [8]u8,
    rdevmajor   : [8]u8,
    rdevminor   : [8]u8,
    namesize    : [8]u8,
    check       : [8]u8,

    pub fn isValid(this : *@This()) void {
        // We only support New ASCII Format
        return std.mem.eql(u8, &this.magic, "070701");
    }

    pub fn isTrailer(this : *@This()) void {
        const ptr : [*]const u8 = @as([*]@This(), this) + 1;
        return std.mem.eql(u8, ptr[0..], "TRAILER!!!");
    }
};

pub const Mode = packed struct(u64) {
    const Prot = packed struct(u3) {
        read : bool,
        write : bool,
        execute : bool,
    };

    world : Prot,
    group : Prot,
    user    : Prot,
    sticky  : bool,
    sgid    : bool,
    suid    : bool,
    fileType : enum(u4) {
        FIFO = 0o1,
        CHAR_DEV = 0o2,
        DIR = 0o4,
        BLOCK_DEV = 0o6,
        REGULAR = 0o10,
        SYM_LINK = 0o12,
        SOCKET = 0o14,
    },
    __pad : u48,
};

// Parse a CPIO into a file system
pub fn parseIntoRamFS(start : *Header) *kernel.fs.vfs.SuperBlock {
    _ = start;
}