const vmm = @import("kernel").mm.vmm;

pub const Process = struct {
    addr_space : vmm.VmSpace,
};

pub const kernel_process : Process = undefined;