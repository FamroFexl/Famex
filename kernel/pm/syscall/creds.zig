const kernel = @import("kernel");
const cast = kernel.cast;
const bin = kernel.bin;

const cpu = @import("arch").cpu;

const posix = @import("lib").posix;
const types = posix.types;

const SysRet = @import("syscall.zig").SysRet;

fn privileged(process : *kernel.Process) bool {
    return process.creds.euid == 0;
}

pub fn setreuid(state : *cpu.CpuState) SysRet {
    const ruid = bin.convert(types.uid_t, state.getArgSys(0).*);
    const euid = bin.convert(types.uid_t, state.getArgSys(1).*);

    const process = kernel.cThread().owner;

    process.spinlock.lock();
    defer process.spinlock.unlock();

    const creds = process.creds;

    const hasPriv = privileged(process);

    // Privilege error EUID
    if (!hasPriv and
        euid != -1 and
        euid != creds.ruid and
        euid != creds.euid and
        euid != creds.suid)
        return .fail(.EPERM);

    if (!hasPriv and ruid != -1)
        return .fail(.EPERM);

    // This must be checked before the values are changed
    if (ruid != -1 or (euid != -1 and euid != creds.ruid))
        creds.suid = euid;

    if (ruid != -1)
        creds.ruid = ruid;
        creds.euid = euid;

    return .ok(0);
}

pub fn setregid(state : *cpu.CpuState) SysRet {
    const rgid = bin.convert(types.gid_t, state.getArgSys(0).*);
    const egid = bin.convert(types.gid_t, state.getArgSys(1).*);

    const process = kernel.cThread().owner;

    process.spinlock.lock();
    defer process.spinlock.unlock();

    const creds = process.creds;

    const hasPriv = privileged(process);

    // Privilege error EGID
    if (!hasPriv and
        egid != creds.sgid and
        egid != creds.rgid)
        return .fail(.EPERM);

    // Privilege error RGID
    if (!hasPriv and
        rgid != creds.sgid)
        return .fail(.EPERM);

    if (rgid != -1 or (egid != -1 and egid != creds.rgid))
        creds.sgid = egid;

    if (rgid != -1)
        creds.rgid = rgid;

    if (egid != -1)
        creds.egid = egid;

    return .ok(0);
}

pub fn setuid(state : *cpu.CpuState) SysRet {
    const uid = bin.convert(types.uid_t, state.getArgSys(0).*);

    const process = kernel.cThread().owner;

    process.spinlock.lock();
    defer process.spinlock.unlock();

    const creds = process.creds;

    const hasPriv = privileged(process);

    // Privilege error UID
    if (!hasPriv and uid != creds.ruid and uid != creds.suid)
        return .fail(.EPERM);

    if (!hasPriv) {
        creds.euid = uid;
        return .ok(0);
    }

    creds.ruid = uid;
    creds.euid = uid;
    creds.suid = uid;

    return .ok(0);
}

pub fn setegid(state : *cpu.CpuState) SysRet {
    const gid = bin.convert(types.gid_t, state.getArgSys(0).*);

    const process = kernel.cThread().owner;

    process.spinlock.lock();
    defer process.spinlock.unlock();

    const creds = process.creds;

    const hasPriv = privileged(process);

    // Privilege error GID
    if (!hasPriv and gid != creds.rgid and gid != creds.sgid)
        return .fail(.EPERM);

    creds.egid = gid;

    return .ok(0);
}

pub fn setgid(state : *cpu.CpuState) SysRet {
    const gid = bin.convert(types.gid_t, state.getArgSys(0).*);

    const process = kernel.cThread().owner;

    process.spinlock.lock();
    defer process.spinlock.unlock();

    const creds = process.creds;

    const hasPriv = privileged(process);

    // Privilege error UID
    if (!hasPriv and gid != creds.rgid and gid != creds.sgid)
        return .fail(.EPERM);

    if (!hasPriv) {
        creds.egid = gid;
        return .ok(0);
    }

    creds.rgid = gid;
    creds.egid = gid;
    creds.sgid = gid;

    return .ok(0);
}

pub fn setresgid(state : *cpu.CpuState) SysRet {
    const rgid = bin.convert(types.gid_t, state.getArgSys(0).*);
    const egid = bin.convert(types.gid_t, state.getArgSys(1).*);
    const sgid = bin.convert(types.gid_t, state.getArgSys(2).*);

    const process = kernel.cThread().owner;

    process.spinlock.lock();
    defer process.spinlock.unlock();

    const creds = process.creds;

    const hasPriv = privileged(process);

    if (!hasPriv) {
        var setRgid = false;
        var setEgid = false;
        var setSgid = false;

        const set = [_]types.gid_t{creds.rgid, creds.egid, creds.sgid};

        for (0..3) |i| {
            if (rgid == set[i])
                setRgid = true;
            if (egid == set[i])
                setEgid = true;
            if (sgid == set[i])
                setSgid = true;
        }

        if ((rgid != -1 and !setRgid) or
            (egid != -1 and !setEgid) or
            (sgid != -1 and !setSgid))
            return .fail(.EPERM);
    }

    if (rgid != -1)
        creds.rgid = rgid;

    if (egid != -1)
        creds.egid = egid;

    if (sgid != -1)
        creds.sgid = sgid;

    return .ok(0);
}

pub fn setresuid(state : *cpu.CpuState) SysRet {
    const ruid = bin.convert(types.uid_t, state.getArgSys(0).*);
    const euid = bin.convert(types.uid_t, state.getArgSys(1).*);
    const suid = bin.convert(types.uid_t, state.getArgSys(2).*);

    const process = kernel.cThread().owner;

    process.spinlock.lock();
    defer process.spinlock.unlock();

    const creds = process.creds;

    const hasPriv = privileged(process);

    if (!hasPriv) {
        var setRuid = false;
        var setEuid = false;
        var setSuid = false;

        const set = [_]types.gid_t{creds.ruid, creds.euid, creds.suid};

        for (0..3) |i| {
            if (ruid == set[i])
                setRuid = true;
            if (euid == set[i])
                setEuid = true;
            if (suid == set[i])
                setSuid = true;
        }

        if ((ruid != -1 and !setRuid) or
            (euid != -1 and !setEuid) or
            (suid != -1 and !setSuid))
            return .fail(.EPERM);
    }

    if (ruid != -1)
        creds.ruid = ruid;

    if (euid != -1)
        creds.euid = euid;

    if (suid != -1)
        creds.suid = suid;

    return .ok(0);
}

pub fn setpgid(state : *cpu.CpuState) SysRet {
    const pid = bin.convert(types.pid_t, state.getArgSys(0).*);
    const pgid = bin.convert(types.pid_t, state.getArgSys(1).*);

    if (pid < 0 or pgid < 0)
        return .fail(.EPERM);

    const process = if (pid == 0) kernel.cThread().owner else
        cast.toPtr(*kernel.Process, kernel.pm.process.pids.get(pid) orelse {
        return .fail(.ESRCH);
    });

    // Check process is current or child
    if (process != kernel.cThread().owner) {
        if (process.owner != kernel.cThread().owner) {
            return .fail(.ESRCH);
        }
        else if (process.flags.HAS_EXECED)
            return .fail(.EACCES);
    }

    var pgroup = if (pgid == 0) process.pgid orelse brk: {
        const newGroup = kernel.pmalloc(kernel.pm.process.Pgid);
        newGroup.pid = process.pid;
        newGroup.list.init();
        kernel.pm.process.pgids.set(process.pid, newGroup);

        break :brk newGroup;
    } else cast.toPtr(*kernel.pm.process.Pgid, kernel.pm.process.pgids.get(pgid) orelse {
        return .fail(.EINVAL);
    });

    process.pgid = pgroup;
    pgroup.list.insertFront(&process.pgidLink);

    return .ok(0);
}

pub fn getpgid(state : *cpu.CpuState) SysRet {
    const pid = bin.convert(types.pid_t, state.getArgSys(0).*);

    if (pid < 0)
        return .fail(.EINVAL);

    const process = if (pid == 0) kernel.cThread().owner else
        cast.toPtr(*kernel.Process, kernel.pm.process.pids.get(@intCast(pid)) orelse {
        return .fail(.ESRCH);
    });

    return .ok(process.pgid.pid);
}

pub fn setsid(state : *cpu.CpuState) SysRet {
    _ = state;

    const process = kernel.cThread().owner;

    const pgid = process.pgid;

    if (kernel.pm.process.pgids.get(process.pid))
        return .fail(.EPERM);

    if (pgid.pid == process.pid)
        return .fail(.EPERM);

    pgid.list.remove(&process.pgidLink);

    if (pgid.list.empty()) {
        const session = pgid.session;
        session.list.remove(&pgid.sessionLink);

        if (session.list.empty()) {
            kernel.pfree(kernel.pm.process.Session, session);
        }

        kernel.pm.process.pgids.free(pgid.pid);
        kernel.pfree(kernel.pm.process.Pgid, pgid);
    }

    const pgroup = kernel.pmalloc(kernel.pm.process.Pgid);
    pgroup.list.init();
    pgroup.pid = process.pid;

    kernel.pm.process.pgids.set(@intCast(process.pid), pgroup);

    process.pgid = pgroup;
    pgroup.list.insertFront(&process.pgidLink);

    const session = kernel.pmalloc(kernel.pm.process.Session);
    session.list.init();
    session.pid = pgroup.pid;
    session.list.insertFront(&pgroup.sessionLink);

    pgroup.session = session;

    return .ok(session.pid);
}

pub fn getsid(state : *cpu.CpuState) SysRet {
    const pid = bin.convert(types.pid_t, state.getArgSys(0).*);

    if (pid < 0)
        return .fail(.EINVAL);

    const process = if (pid == 0) kernel.cThread().owner else
        cast.toPtr(*kernel.Process, kernel.pm.process.pids.get(@intCast(pid)) orelse {
        return .fail(.ESRCH);
    });

    return .ok(process.pgid.session.pid);
}