const std = @import("std");

const kernel = @import("kernel");

const vfs = kernel.fs.vfs;
const Dentry = vfs.Dentry;
const Inode = vfs.Inode;
const File = vfs.File;
const FSError = vfs.FSError;

pub const RamFS = vfs.FileSystemOps {
    .mkReg = mkReg,
    .mkDir = mkDir,
    .mkDev = mkDev,
    .mkSymLink = mkSymLink,
    .mkLink = mkLink,
    .unlink = unlink,
    .open = open,
    .readSymLink = readSymLink,
    .syncNode = syncNode,
};

const RFSInode = struct {
    entry : union {
        symLink : []const u8,   // Stores symlink if symbolic
        dentry : *Dentry,       // Directory entry reference
        deviceID : u64,         // Device ID for dev files
    },
    base : vfs.Inode,
};

const ChunkList = kernel.util.data.ListTyped(DataChunk, "link");

const DataChunk = struct {
    pub const PagesPerChunk = 13;

    pages : [PagesPerChunk]kernel.Vaddr,

    section : u64,  // Which section the page chunk represents (section * PagesPerChunk)
    link : ChunkList.Node,
};

const RFSFile = struct {
    base : vfs.File,
    chunks : ChunkList,
};

const RFSFileSystem = struct {
    base : vfs.FileSystem,
};

fn mkDir(parent : *Dentry, name : []const u8) vfs.MakeError!*Dentry {
    const inode = kernel.pmalloc(RFSInode);
    errdefer kernel.pfree(RFSInode, inode);

    const newEntry = try vfs.resolveName(parent, inode, name);

    inode.base.init(.DIRECTORY, parent.inode.?.fs);
    inode.entry.dentry = newEntry;
}

fn mkReg(parent : *Dentry, name : []const u8) vfs.MakeError!*Dentry {
    const newEntry = vfs.createDentry(parent, name);

    const inode = kernel.pmalloc(RFSInode);
    newEntry.inode = &inode.base;

    inode.base.createTime = kernel.getUnixClock();
    inode.base.nodeType = .REGULAR;
    inode.base.fs = parent.inode.?.fs;

    inode.base.links = 1;

    return newEntry;
}

fn mkDev(parent : *Dentry, name : []const u8) vfs.MakeError!*Dentry {

}

fn mkSymLink(parent : *Dentry, name : []const u8, path : []const u8) vfs.MakeError!*Dentry {
    const newEntry = vfs.createDentry(parent, name);
    const inode = kernel.pmalloc(RFSInode);
    newEntry.inode = &inode.base;

    inode.base.createTime = kernel.getUnixClock();
    inode.base.nodeType = .SYM_LINK;
    inode.base.fs = parent.inode.?.fs;

    inode.entry.symLink.ptr = kernel.pmallocBytes(path.len);
    inode.entry.symLink.len = path.len;

    @memcpy(inode.entry.symLink, path);

    return newEntry;
}

fn mkLink(parent : *Dentry, name : []const u8, node : *Inode) .{FSError.IsDirectory, vfs.MakeError}!*Dentry {
    node.spinlock.lock();

    // We don't allow hardlinks to directories
    if (node.nodeType == .DIRECTORY) {
        node.spinlock.unlock();

        return FSError.IsDirectory;
    }


    const newEntry = try vfs.createDentry(parent, name);

    newEntry.inode = node;
    node.links += 1;

    return newEntry;
}

fn unlink(link : *Dentry) void {
    if (link.inode) |inode| {
        if (inode.nodeType == .DIRECTORY) {
            const rfsNode : *RFSInode = @fieldParentPtr("base", inode);
            if (!rfsNode.entry.dentry.children.empty()) {
                // Return inode is directory and directory is not empty
            }
        }

        inode.links -= 1;

        // Remove file
        if (inode.links == 0) {

        }
    }

    vfs.unrefDentry(link);
}

fn open(link : *Dentry) *File {

}

fn readSymLink(node : *Inode) []const u8 {
    //if (node.nodeType != .SYM_LINK)

    const rfsNode : *RFSInode = @fieldParentPtr("base", node);
    return rfsNode.symLink;
}

// The Inode is the backing store on RamFS
fn syncNode(node : *Inode) void {
    _ = node;
}

fn validName(name : []const u8) bool {
    if (std.mem.eql(u8, name, "..") or std.mem.eql(u8, name, "."))
        return true;

    for (name) |char| {
        if (char == 0 or char == '/')
            return false;
    }

    return true;
}
