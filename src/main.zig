const std = @import("std");
const builtin = @import("builtin");
const build_opts = @import("build_opts");
const modules = @import("modules.zig");
const tests = @import("tests.zig");
const c = @import("c.zig");
const cc = @import("cc.zig");
const g = @import("g.zig");
const log = @import("log.zig");
const opt = @import("opt.zig");
const net = @import("net.zig");
const server = @import("server.zig");
const EvLoop = @import("EvLoop.zig");
const co = @import("co.zig");

// ============================================================================

/// the rewrite is to avoid generating unnecessary code in release mode.
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);
    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe)
        std.builtin.default_panic(msg, error_return_trace, ret_addr)
    else
        cc.abort();
}

// ============================================================================

const _debug = builtin.mode == .Debug;

const gpa_t = if (_debug) std.heap.GeneralPurposeAllocator(.{}) else void;
var _gpa: gpa_t = undefined;

const pipe_fds_t = if (_debug) [2]c_int else void;
var _pipe_fds: pipe_fds_t = undefined;

fn on_sigusr1(_: c_int) callconv(.C) void {
    const v: u8 = 0;
    _ = cc.write(_pipe_fds[1], std.mem.asBytes(&v));
}

fn memleak_checker() void {
    defer co.terminate(@frame(), @frameSize(memleak_checker));

    cc.pipe2(&_pipe_fds, c.O_CLOEXEC | c.O_NONBLOCK) orelse {
        log.err(@src(), "pipe() failed: (%d) %m", .{cc.errno()});
        @panic("pipe failed");
    };
    defer _ = cc.close(_pipe_fds[1]); // write end

    // register sig_handler
    _ = cc.signal(c.SIGUSR1, on_sigusr1);

    const fdobj = EvLoop.Fd.new(_pipe_fds[0]);
    defer fdobj.free(); // read end

    while (true) {
        var v: u8 = undefined;
        _ = g.evloop.read(fdobj, std.mem.asBytes(&v)) orelse {
            log.err(@src(), "read(%d) failed: (%d) %m", .{ fdobj.fd, cc.errno() });
            continue;
        };
        log.info(@src(), "signal received, check memory leaks ...", .{});
        _ = _gpa.detectLeaks();
    }
}

// ============================================================================

/// called by EvLoop.check_timeout
// pub const check_timeout = server.check_timeout;
pub fn check_timeout() c_int {
    // TODO
    return -1;
}

pub fn main() u8 {
    g.allocator = if (_debug) b: {
        _gpa = gpa_t{};
        break :b _gpa.allocator();
    } else std.heap.c_allocator;

    defer {
        if (_debug)
            _ = _gpa.deinit();
    }

    // ============================================================================

    _ = cc.signal(c.SIGPIPE, cc.SIG_IGN());

    _ = cc.setvbuf(cc.stdout, null, c._IOLBF, 256);

    // setting default values for TZ
    _ = cc.setenv("TZ", ":/etc/localtime", false);

    // ============================================================================

    // used only for business-independent initialization, such as global variables
    init_all_module();
    defer if (_debug) deinit_all_module();

    // ============================================================================

    if (build_opts.is_test)
        return tests.main();

    // ============================================================================

    opt.parse();

    net.init();

    const src = @src();
    _ = src; // autofix

    // ============================================================================

    // TODO: multi threads
    g.evloop = EvLoop.init();

    server.start();

    if (_debug)
        co.create(memleak_checker, .{});

    g.evloop.run();

    return 0;
}

fn init_all_module() void {
    comptime var i = 0;
    inline while (i < modules.module_list.len) : (i += 1) {
        const module = modules.module_list[i];
        const module_name: cc.ConstStr = modules.name_list[i];
        if (@hasDecl(module, "module_init")) {
            if (false) log.debug(@src(), "%s.module_init()", .{module_name});
            module.module_init();
        }
    }
}

fn deinit_all_module() void {
    comptime var i = 0;
    inline while (i < modules.module_list.len) : (i += 1) {
        const module = modules.module_list[i];
        const module_name: cc.ConstStr = modules.name_list[i];
        if (@hasDecl(module, "module_deinit")) {
            if (false) log.debug(@src(), "%s.module_deinit()", .{module_name});
            module.module_deinit();
        }
    }
}
