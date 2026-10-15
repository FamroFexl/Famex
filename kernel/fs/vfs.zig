const std = @import("std");

const kernel = @import("kernel");

pub var ROOT : *Dentry = undefined;

pub const MakeError = error {
    InvalidName,    // Name is invalid by standard or custom FS rule sets
    NameExists,     // Name already exists in directory
    NotDirectory,   // File is not a directory
};

pub const FSError = error {
    NameNotFound,       // File Not found
    IsDirectory,        // File is a directory
    DirectoryNotEmpty,  // Directory cannot be unlinked. It is not empty
    NotFile,            // Dentry does not contain a file
    NotSameFS,          // Not the same file system
} || MakeError;

// Valid names must support ".." and "." and must not contain '\0' or '/'

/// Semantics
/// A dentry's inode cannot be modified unless the dentry lock is held.
///
/// Lock the dentry first, and then the inode.
///
/// Lock the parent dentry first, and then the child. Usually this isn't necessary since the child can't be
/// freed while the parent lock is held, and the child can be refcounted in the lock.
///
/// A dentry cannot be freed unless it's inode field is null, it's children list is empty, and it's references are 0.
///
/// An inode cannot be freed unless it's dentry list is empty and it's references are 0.

/// Output Dentry is ref-counted before returned.
/// Parent must be ref-counted before.
fn resolveName(parent : *Dentry, name : []const u8) .{MakeError.NotDirectory, MakeError.InvalidName}!*Dentry {
    if (std.mem.eql(u8, name, ".")) {
        parent.refCount.incr();
        Dentry.Lru.touch(parent);
        return parent;
    }

    // We return the parent, which may be itself if it is the root
    if (std.mem.eql(u8, name, "..")) {
        parent.parent.refCount.incr();
        Dentry.Lru.touch(parent.parent);
        return parent.parent;
    }

    // Preallocate and init a new entry before we spinlock
    const newEntry = kernel.pmalloc(Dentry);
    newEntry.name.ptr = kernel.pmallocBytes(name.len);
    newEntry.name.len = name.len;
    @memcpy(newEntry.name, name);
    newEntry = .{};
    newEntry.inode = null;
    newEntry.parent = parent;
    newEntry.children.init();
    newEntry.waitQueue.init();
    newEntry.flags.lookupWait = true;

    parent.spinlock.lock();

    if (!parent.inode or parent.inode.?.nodeType != .DIRECTORY) {
        parent.spinlock.unlock();

        kernel.pfree(Dentry, newEntry);
        kernel.pfree(newEntry.name.ptr);

        return MakeError.NotDirectory;
    }

    if (!parent.inode.?.fs.ops.validName(name)) {
        parent.spinlock.unlock();

        kernel.pfree(Dentry, newEntry);
        kernel.pfree(newEntry.name.ptr);

        return MakeError.InvalidName;
    }

    var iter = parent.children.iterator();
    while (iter.next()) |next| {
        if (std.mem.eql(u8, name, next.name)) {
            next.refCount.incr();

            parent.spinlock.unlock();

            Dentry.Lru.touch(next);

            kernel.pfree(Dentry, newEntry);
            kernel.pfreeBytes(newEntry.name.ptr);

            next.spinlock.lock();

            const thread = kernel.cThread();

            while (next.flags.lookupWait) {
                next.waitQueue.sleep(thread, &next.spinlock, .UNINTERRUPTIBLE);
            }

            next.spinlock.unlock();

            return next;
        }
    }

    parent.children.insertFront(newEntry);

    const dentryNode = parent.inode.?;
    dentryNode.refCount.incr();

    parent.spinlock.unlock();

    // Backing storage lookup
    const lookup = dentryNode.lookup(name);

    // This node can't be freed because a child node is
    // performing a lookup
    dentryNode.refCount.decr();

    newEntry.spinlock.lock();
    newEntry.flags.lookupWait = false;
    newEntry.inode = lookup;

    if (lookup) |node| {
        node.spinlock.lock();
        node.dentries.insertFront(newEntry);
        node.spinlock.unlock();

        node.refCount.decr();
    }

    newEntry.spinlock.unlock();

    Dentry.Lru.add(newEntry);

    newEntry.waitQueue.wakeAll();

    return newEntry;
}

// Helper function for VFS generic file creation
fn makeFile(this : *Dentry, name : []const u8, link : anytype, comptime createType : enum {DIR, REG, DEV, SYM, LINK}) MakeError!*Dentry {
    const dentry : *Dentry = try resolveName(this, name);

    dentry.spinlock.lock();
    if (dentry.inode) {
        dentry.spinlock.unlock();

        return MakeError.NameExists;
    }
    dentry.flags.lookupWait = true;
    dentry.spinlock.unlock();

    this.spinlock.lock();
    const inode = this.inode.?;
    this.spinlock.unlock();

    const child = switch (createType) {
        .REG => inode.fs.ops.mkReg(inode, name),
        .DIR => inode.fs.ops.mkDir(inode, name),
        .DEV => inode.fs.ops.mkDev(inode, name),
        .SYM => inode.fs.ops.mkSymLink(inode, name, link),
        .LINK => inode.fs.ops.mkLink(inode, name, link),
    };

    dentry.spinlock.lock();
    dentry.flags.lookupWait = false;
    dentry.inode = child;

    inode.spinlock.lock();
    inode.dentries.insertFront(dentry);
    inode.spinlock.unlock();

    dentry.spinlock.unlock();

    dentry.waitQueue.wakeAll();

    return dentry;
}

pub fn walkPath(root : *Dentry, path : []const u8) .{FSError.InvalidName, FSError.NameNotFound, FSError.NotDirectory}!*Dentry {
    const names = std.mem.splitScalar(u8, path, '/');

    var cur = root;

    while (names.next()) |name| {
        if (name.len == 0)
            continue;

        const old = cur;

        errdefer cur.refCount.decr();

        cur = try cur.resolve(name);

        if (old != ROOT)
            old.refCount.decr();
    }

    return cur;
}

// Inode to dentry links
const InodeDentryList = kernel.ListTyped(Dentry, "inodeLink");

pub const Dentry = struct {
    const DentryLru = kernel.LruList(Dentry, "lruLink");
    pub const Lru : DentryLru = undefined;

    // Dentry children list
    const ChildDentryList = kernel.ListTyped(Dentry, "link");

    // Constant
    parent : *Dentry = undefined,

    children : ChildDentryList = undefined,

    // Parent list link
    link : ChildDentryList.Node = undefined,

    // Link for inodes to find reference dentries
    inodeLink : InodeDentryList.Node = undefined,

    lruLink : DentryLru.Node = undefined,

    // Constant
    name : []const u8 = undefined,

    inode : ?*Inode = null,

    spinlock : kernel.Spinlock = .create(),
    refCount : kernel.RefCount = .create(),

    flags : packed struct {
        lookupWait : bool,  // Is currently performing a backing storage lookup
    } = undefined,

    // Waiting threads
    waitQueue : kernel.util.WaitQueue = undefined,
    
    pub fn resolve(this : *@This(), name : []const u8) .{FSError.InvalidName, FSError.NameNotFound, FSError.NotDirectory}!*Dentry {
        const dentry : *Dentry = try resolveName(this, name);
        
        dentry.spinlock.lock();
        defer dentry.spinlock.unlock();
        
        if (dentry.inode == null)
            return FSError.NameNotFound;
        
        return dentry;
    }

    pub fn mkReg(this : *@This(), name : []const u8) MakeError!*Dentry {
        return makeFile(this, name, null, .REG);
    }

    pub fn mkDir(this : *@This(), name : []const u8) MakeError!*Dentry {
        return makeFile(this, name, null, .DIR);
    }

    pub fn mkDev(this : *@This(), name : []const u8) MakeError!*Dentry {
        return makeFile(this, name, null, .DEV);
    }

    pub fn mkSymLink(this : *@This(), name : []const u8, path : []const u8) MakeError!*Dentry {
        return makeFile(this, name, path, .SYM);
    }

    pub fn mkLink(this : *@This(), name : []const u8, node : *Inode) .{FSError.IsDirectory, MakeError}!*Dentry {
        return makeFile(this, name, node, .LINK);
    }

    pub fn unlink(this : *@This()) .{FSError.NotFile, FSError.DirectoryNotEmpty}!void {
        this.parent.spinlock.lock();
        const parentInode = this.parent.inode.?;
        parentInode.refCount.incr();
        this.parent.spinlock.unlock();

        this.spinlock.lock();
        if (!this.children.empty()) {
            this.spinlock.unlock();

            return FSError.NotFile;
        }
        const inode = this.inode orelse {
            this.spinlock.unlock();

            parentInode.refCount.decr();

            return FSError.NotFile;
        };
        inode.refCount.incr();

        this.flags.lookupWait = true;
        this.spinlock.unlock();

        inode.fs.ops.unlink(parentInode, inode) catch {
            return FSError.DirectoryNotEmpty;
        };

        this.spinlock.lock();
        this.flags.lookupWait = false;
        this.spinlock.unlock();

        this.waitQueue.wakeAll();
    }

    pub fn rename(src : *Dentry, dstParent : *Dentry, dstName : []const u8) .{FSError.NotSameFS, MakeError}!void {

        if (src.inode.?.fs != dstParent.inode.?.fs) {
            return FSError.NotSameFS;
        }

        dstParent.inode.?.fs.ops.lookup(dstParent.inode.?, dstName);

        src.spinlock.lock();
        const inode = src.inode.?;
    }

    pub fn open(this : *@This()) FSError.NotFile!*File {
        this.spinlock.lock();
        const inode = this.inode orelse {
            this.spinlock.unlock();
            return FSError.NotFile;
        };
        inode.refCount.incr();
        this.spinlock.unlock();

        return inode.fs.ops.open(inode);
    }
};

pub const NodeType = enum {
    REGULAR,
    DIRECTORY,
    DEVICE,
    SYM_LINK,
};

pub const Inode = struct {
    // Constant
    fs : *FileSystem = undefined,

    createTime : kernel.Time = undefined,
    lastRead : kernel.Time = undefined,
    lastWrite : kernel.Time = undefined,

    gid : kernel.pm.process.Pid = undefined,
    pid : kernel.pm.process.Pid = undefined,

    size : usize = undefined,
    links : u64 = 1, // Number of hard links to this inode

    dentries : InodeDentryList = undefined,

    flags : packed struct {
        setUid : bool,
        setGid : bool,
        sticky : bool,

        user : Prot,
        group : Prot,
        other : Prot,

        const Prot = packed struct {
            read : bool,
            write : bool,
            execute : bool,
        };
    } = undefined,

    // Constant
    nodeType : NodeType = undefined,

    spinlock : kernel.Spinlock = .create(),
    refCount : kernel.RefCount = .create(),

    pub fn readSymLink(this : *@This()) []const u8 {
        return this.fs.ops.readSymLink(this);
    }

    pub fn sync(this : *@This()) void {
        kernel.lockHeld(&this.spinlock);

        this.fs.ops.syncNode(this);
    }

    /// Input node is refcounted and output node is refcounted
    pub fn lookup(this : *@This(), name : []const u8) ?*Inode {
        kernel.lockHeld(&this.spinlock);

        return this.fs.ops.lookup(this, name);
    }

    pub const init = initInode;
};

pub fn initInode(inode : *Inode, nodeType : NodeType, fs : *FileSystem) void {
    inode.spinlock.lock();
    defer inode.spinlock.unlock();

    inode.nodeType = nodeType;
    inode.fs = fs;

    inode = .{};
}

pub const File = struct {
    dentry : *Dentry,

    offset : usize, // Current seek offset

    pub fn seek(this : *@This(), offset : usize) void {
        this.dentry.inode.?.fs.ops.seek(this, offset);
    }

    pub fn read(this : *@This(), addr : *anyopaque, size : usize) void {
        this.dentry.inode.?.fs.ops.read(this, addr, size);
    }

    pub fn write(this : *@This(), addr : * const anyopaque, size : usize) void {
        this.dentry.inode.?.fs.ops.write(this, addr, size);
    }

    pub fn mmap(this : *@This(), area : *kernel.mm.vmm.VmArea) void {
        this.dentry.inode.?.fs.ops.mmap(this, area);
    }

    pub fn sync(this : *@This()) void {
        this.dentry.inode.?.fs.ops.syncFile(this);
    }

    pub fn close(this : *@This()) void {
        this.dentry.inode.?.fs.ops.close(this);
    }
};

pub const FileSystemOps = struct {
    // File System ops
    mount : *const fn (fs : *FileSystem, parent : *Dentry) void,
    unmount : *const fn (fs : *FileSystem, parent : *Dentry) void,

    syncFs : *const fn (fs : *FileSystem) void,

    // Inode ops
    validName : *const fn (name : []const u8) bool,

    mkReg : *const fn (parent : *Inode, name : []const u8) *Inode,
    mkDir : *const fn (parent : *Inode, name : []const u8) *Inode,
    mkDev : *const fn (parent : *Inode, name : []const u8) *Inode,
    mkSymLink : *const fn (parent : *Inode, name : []const u8, path : []const u8) *Inode,
    mkLink : *const fn (parent : *Inode, name : []const u8, node : *Inode) *Inode,

    unlink : *const fn (parent : *Inode, node : *Inode) FSError.DirectoryNotEmpty!void,

    rename : *const fn (srcParent : *Inode, src : *Inode, dstParent : *Inode, dst : []const u8) void,

    open : *const fn (node : *Inode) *File,

    // Inode ops
    readSymLink : *const fn (node : *Inode) []const u8,

    // Lookup a name in a directory that isn't cached as a dentry. (Parent dentry must be spinlocked)
    lookup : *const fn (node : *Inode, name : []const u8) ?*Inode,

    syncNode : *const fn (node : *Inode) void,

    // File Ops
    seek : *const fn (file : *File, offset : usize) void,
    read : *const fn (file : *File, addr : *anyopaque, size : usize) void,
    write : *const fn (file : *File, addr : *const anyopaque, size : usize) void,

    mmap : *const fn (file : *File, area : *kernel.mm.vmm.VmArea) void,

    syncFile : *const fn (file : *File) void,

    close : *const fn (file : *File) void,
};

pub const FileSystem = struct {
    ops : *FileSystemOps,

    root : *Dentry,

    pub fn mount(this : *@This(), parent : *Dentry) void {
        this.ops.mount(this, parent);
    }

    pub fn unmount(this : *@This(), parent : *Dentry) void {
        this.ops.unmount(this, parent);
    }

    pub fn sync(this : *@This()) void {
        this.ops.syncFs(this);
    }
};

pub fn setup() void {
    Dentry.Lru.init();
}