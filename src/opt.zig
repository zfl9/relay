const std = @import("std");
const builtin = @import("builtin");
const build_opts = @import("build_opts");
const c = @import("c.zig");
const cc = @import("cc.zig");
const g = @import("g.zig");
const log = @import("log.zig");
const str2int = @import("str2int.zig");
const assert = std.debug.assert;

const help =
    \\usage: relay <options...>
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

// ================================================================

comptime {
    // @compileLog("sizeof(OptDef):", @sizeOf(OptDef), "alignof(OptDef):", @alignOf(OptDef));
    // @compileLog("sizeof([]const u8):", @sizeOf([]const u8), "alignof([]const u8):", @alignOf([]const u8));
    // @compileLog("sizeof(OptFn):", @sizeOf(OptFn), "alignof(OptFn):", @alignOf(OptFn));
    // @compileLog("sizeof(enum{a,b,c}):", @sizeOf(enum { a, b, c }), "alignof(enum{a,b,c}):", @alignOf(enum { a, b, c }));
}

const OptDef = struct {
    short: []const u8, // short name
    long: []const u8, // long name
    optfn: OptFn,
    value: enum { required, optional, no_value },
};

const OptFn = std.meta.FnPtr(fn (in_value: ?[]const u8) void);

// zig fmt: off
const optdef_array = [_]OptDef{
    .{ .short = "C", .long = "config",  .value = .required, .optfn = opt_config,  },
    .{ .short = "v", .long = "verbose", .value = .no_value, .optfn = opt_verbose, },
    .{ .short = "V", .long = "version", .value = .no_value, .optfn = opt_version, },
    .{ .short = "h", .long = "help",    .value = .no_value, .optfn = opt_help,    },
};
// zig fmt: on

noinline fn get_optdef(name: []const u8) ?OptDef {
    if (name.len == 0)
        return null;

    for (optdef_array) |optdef| {
        if (std.mem.eql(u8, optdef.short, name) or std.mem.eql(u8, optdef.long, name))
            return optdef;
    }

    return null;
}

// ================================================================

/// print(fmt, args)
pub fn printf(comptime src: std.builtin.SourceLocation, comptime fmt: [:0]const u8, args: anytype) void {
    cc.printf("%s " ++ fmt ++ "\n", .{comptime log.srcinfo(src).ptr} ++ args);
}

/// print("msg: value")
pub fn print(comptime src: std.builtin.SourceLocation, msg: [:0]const u8, value: []const u8) void {
    printf(src, "%s: '%.*s'", .{ msg.ptr, cc.to_int(value.len), value.ptr });
}

/// print(fmt, args) + print(help) + exit(1)
fn printf_exit(comptime src: std.builtin.SourceLocation, comptime fmt: [:0]const u8, args: anytype) noreturn {
    printf(src, fmt, args);
    cc.printf("%s\n", .{help});
    cc.exit(1);
}

/// print("msg: value") + print(help) + exit(1)
fn print_exit(comptime src: std.builtin.SourceLocation, msg: [:0]const u8, value: []const u8) noreturn {
    printf_exit(src, "%s: '%.*s'", .{ msg.ptr, cc.to_int(value.len), value.ptr });
}

/// print("invalid opt-value: value") + print(help) + exit(1)
fn invalid_optvalue(comptime src: std.builtin.SourceLocation, value: []const u8) noreturn {
    print_exit(src, "invalid opt-value", value);
}

// ================================================================

fn opt_config(in_value: ?[]const u8) void {
    // prevent stack overflow due to recursion
    const static = struct {
        var depth: u8 = 0;
    };

    const src = @src();
    const filename = in_value.?;

    if (static.depth + 1 > 10)
        print_exit(src, "config chain is too deep", filename);

    static.depth += 1;
    defer static.depth -= 1;

    if (filename.len > c.PATH_MAX)
        print_exit(src, "filename is too long", filename);

    const mem = cc.mmap_file(cc.to_cstr(filename)) orelse
        printf_exit(src, "failed to open file: '%.*s' (%m)", .{ cc.to_int(filename.len), filename.ptr });
    defer _ = cc.munmap(mem);

    var line_it = std.mem.split(u8, mem, "\n");
    while (line_it.next()) |line| {
        const err: cc.ConstStr = e: {
            // optname [optvalue]
            var it = std.mem.tokenize(u8, line, " \t\r");

            const optname = it.next() orelse continue;

            if (std.mem.startsWith(u8, optname, "#")) continue;

            const optvalue = it.next();

            if (it.next() != null)
                break :e "too many values";

            const optdef = get_optdef(optname) orelse
                break :e "unknown option";

            switch (optdef.value) {
                .required => {
                    if (optvalue == null)
                        break :e "missing opt-value";
                },
                .no_value => {
                    if (optvalue != null)
                        break :e "unexpected opt-value";
                },
                else => {},
            }

            if (optvalue != null and optvalue.?.len <= 0)
                break :e "invalid format";

            optdef.optfn(optvalue);

            continue;
        };

        // error handling
        printf_exit(src, "'%.*s': %s: %.*s", .{ cc.to_int(filename.len), filename.ptr, err, cc.to_int(line.len), line.ptr });
    }
}

pub noinline fn check_ip(value: []const u8) ?void {
    if (cc.ip_family(cc.to_cstr(value)) == null) {
        print(@src(), "invalid ip", value);
        return null;
    }
}

pub noinline fn check_port(value: []const u8) ?u16 {
    const port = str2int.parse(u16, value, 10) orelse 0;
    if (port == 0) {
        print(@src(), "invalid port", value);
        return null;
    }
    return port;
}

fn opt_verbose(_: ?[]const u8) void {
    g.flags.add(.verbose);
}

fn opt_version(_: ?[]const u8) void {
    cc.printf("%s\n", .{version});
    cc.exit(0);
}

fn opt_help(_: ?[]const u8) void {
    cc.printf("%s\n", .{help});
    cc.exit(0);
}

// ================================================================

const Parser = struct {
    idx: usize,

    pub fn init() Parser {
        return .{ .idx = 1 };
    }

    pub noinline fn parse(self: *Parser) void {
        const arg = self.pop_arg() orelse return;

        const err: [:0]const u8 = e: {
            if (std.mem.startsWith(u8, arg, "--")) {
                if (arg.len < 4)
                    break :e "invalid long option";

                // --name
                // --name=value
                // --name value
                if (std.mem.indexOfScalar(u8, arg, '=')) |sep|
                    self.handle(arg[2..sep], arg[sep + 1 ..])
                else
                    self.handle(arg[2..], null);
                //
            } else if (std.mem.startsWith(u8, arg, "-")) {
                if (arg.len < 2)
                    break :e "invalid short option";

                // -x
                // -x5
                // -x=5
                // -x 5
                if (arg.len == 2)
                    self.handle(arg[1..], null)
                else if (arg[2] == '=')
                    self.handle(arg[1..2], arg[3..])
                else
                    self.handle(arg[1..2], arg[2..]);
                //
            } else {
                break :e "expect an option, got the pos-argument";
            }

            return @call(.{ .modifier = .always_tail }, Parser.parse, .{self});
        };

        // error handling
        print_exit(@src(), err, arg);
    }

    noinline fn peek_arg(self: Parser) ?[:0]const u8 {
        const argv = std.os.argv;

        return if (self.idx < argv.len)
            cc.strslice_c(argv[self.idx])
        else
            null;
    }

    noinline fn pop_arg(self: *Parser) ?[:0]const u8 {
        if (self.peek_arg()) |arg| {
            self.idx += 1;
            return arg;
        }
        return null;
    }

    noinline fn take_value(self: *Parser, name: []const u8, required: bool) ?[:0]const u8 {
        const arg = self.peek_arg() orelse {
            if (required)
                print_exit(@src(), "expect a value for option", name);
            return null;
        };

        if (required or !std.mem.startsWith(u8, arg, "-")) {
            _ = self.pop_arg();
            return arg;
        }

        return null;
    }

    noinline fn handle(self: *Parser, name: []const u8, in_value: ?[:0]const u8) void {
        const src = @src();

        const optdef = get_optdef(name) orelse
            print_exit(src, "unknown option", name);

        const value = switch (optdef.value) {
            .required => if (in_value) |v| v else self.take_value(name, true),
            .optional => if (in_value) |v| v else self.take_value(name, false),
            .no_value => if (in_value == null) null else {
                printf_exit(src, "option '%.*s' not accept value: '%s'", .{ cc.to_int(name.len), name.ptr, in_value.?.ptr });
            },
        };

        if (value != null and value.?.len <= 0)
            printf_exit(src, "option '%.*s' not accept empty string", .{ cc.to_int(name.len), name.ptr });

        optdef.optfn(value);
    }
};

// ================================================================

pub fn parse() void {
    @setCold(true);

    var parser = Parser.init();
    parser.parse();
}
