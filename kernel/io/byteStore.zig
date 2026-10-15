// Block device interface
pub const ByteStoreOps = struct {
    read : *const fn (bs : *ByteStore, offset : usize, buffer : []u8) void,
    write : *const fn (bs : *ByteStore, offset : usize, buffer : []const u8) void,
};

pub const ByteStore = struct {
    ops : *ByteStoreOps,

    // Size of the block store
    size : usize,

    pub fn read(this : *@This(), offset : usize, buffer : []u8) void {
        const end = @addWithOverflow(offset, buffer.len);
        if (end[1] == 1 or end[0] >= this.size) {

        }

        this.ops.read(this, offset, buffer);
    }

    pub fn write(this : *@This(), offset : usize, buffer : []const u8) void {
        const end = @addWithOverflow(offset, buffer.len);
        if (end[1] == 1 or end[0] >= this.size) {

        }

        this.ops.write(this, offset, buffer);
    }
};

pub const BoundedByteStore = struct {
    start : usize,
    end : usize,

    bs : *ByteStore,

    pub fn read(this : *@This(), offset : usize, buffer : []u8) void {
        const end = @addWithOverflow(offset, buffer.len);
        if (end[1] == 1 or offset < this.start or end[0] >= this.end) {

        }

        this.bs.ops.read(this.bs,offset, buffer);
    }

    pub fn write(this : *@This(), offset : usize, buffer : []u8) void {
        const end = @addWithOverflow(offset, buffer.len);
        if (end[1] == 1 or offset < this.start or end[0] >= this.end) {

        }

        this.bs.ops.write(this.bs,offset, buffer);
    }
};