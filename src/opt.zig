const std = @import("std");
const builtin = @import("builtin");
const build_opts = @import("build_opts");
const cc = @import("cc.zig");
const cfg = @import("cfg.zig");

const help =
    \\usage: relay <config>
    \\ -V, --version    show the version of the program
    \\ see https://github.com/zfl9/relay for more details
;

const version: cc.ConstStr = b: {
    var target: [:0]const u8 = @tagName(builtin.cpu.arch) ++ "-" ++ @tagName(builtin.os.tag) ++ "-" ++ @tagName(builtin.abi);

    if (builtin.target.isGnuLibC())
        target = target ++ std.fmt.comptimePrint(".{}", .{builtin.os.version_range.linux.glibc});

    if (!std.mem.eql(u8, target, build_opts.target))
        @compileError("target-triple mismatch: " ++ target ++ " != " ++ build_opts.target);

    const cpu_model = builtin.cpu.model.name;

    if (!std.mem.startsWith(u8, build_opts.cpu, cpu_model))
        @compileError("cpu-model mismatch: " ++ cpu_model ++ " != " ++ build_opts.cpu);

    var prefix: [:0]const u8 = "relay " ++ build_opts.version ++ " " ++ build_opts.commit_id;

    if (build_opts.enable_wolfssl)
        prefix = prefix ++ " | wolfssl-" ++ build_opts.wolfssl_version;

    break :b std.fmt.comptimePrint("{s} | target:{s} | cpu:{s} | mode:{s} | {s}", .{
        prefix,
        build_opts.target,
        build_opts.cpu,
        build_opts.mode,
        "<https://github.com/zfl9/relay>",
    });
};

pub fn parse() void {
    const argv = std.os.argv;
    if (argv.len != 2) {
        cc.printf("%s\n", .{help});
        cc.exit(0);
    }
    const arg = cc.strslice_c(std.os.argv[1]);
    if (std.mem.startsWith(u8, arg, "-")) {
        if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--version"))
            cc.printf("%s\n", .{version})
        else
            cc.printf("%s\n", .{help});
        cc.exit(0);
    } else {
        cfg.parse(arg);
    }
}
