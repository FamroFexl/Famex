const kernel = @import("kernel");

pub fn LruList(comptime T : type, comptime linkField : []const u8) type {
    return struct {
        const LruTyped = kernel.ListTyped(type, linkField);

        list : LruTyped = undefined,
        spinlock : kernel.Spinlock = .create(),
        count : u64 = 0,

        pub const Node = LruTyped.Node;

        pub fn init(this : *@This()) void {
            this.* = .{};
            this.list.init();
        }

        pub fn touch(this : *@This(), node : *T) void {
            this.spinlock.lock();

            this.list.remove(node);
            this.list.insertFront(node);

            this.spinlock.unlock();
        }

        pub fn add(this : *@This(), node : *T) void {
            this.spinlock.lock();

            this.list.insertFront(node);
            this.count += 1;

            this.spinlock.unlock();
        }
    };
}