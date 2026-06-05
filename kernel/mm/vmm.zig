const Vaddr = @import("memory.zig").Vaddr;
const paging = @import("paging.zig");

pub const VmSpace = struct {
    //vm_lock : spinlock,
    //tree : maple_tree,
    //cpu_mask : cpu_mask,
    start : Vaddr,
    end : Vaddr,
    root_pt : *paging.Ptable,
};

pub fn setup_virt_mem_mgmt() void {

}