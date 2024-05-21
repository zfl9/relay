const std = @import("std");
const c = @import("c.zig");
const cc = @import("cc.zig");
const g = @import("g.zig");
const in = @import("in.zig");
const out = @import("out.zig");
const cfg_global = @import("cfg_global.zig");
const log = @import("log.zig");
const str2int = @import("str2int.zig");
const assert = std.debug.assert;

// ========================================================================

pub const Define = struct {
    name: []const u8,
    func: std.meta.FnPtr(fn (in_value: ?[]const u8) void),
    value: enum { required, optional, no_value },
};

fn get_def(defines: []const Define, name: []const u8) ?Define {
    for (defines) |def| {
        if (std.mem.eql(u8, def.name, name))
            return def;
    }
    return null;
}

// ========================================================================

pub fn parse(filename: cc.ConstStr) void {
    const src = @src();

    const mem = cc.mmap_file(filename) orelse {
        log.err(src, "failed to open file: '%s' (%m)", .{filename});
        cc.exit(1);
    };
    defer _ = cc.munmap(mem);

    var defines: []const Define = &cfg_global.defines;

    var line_it = std.mem.split(u8, mem, "\n");
    while (line_it.next()) |line| {
        const err: cc.ConstStr = e: {
            // # comments
            // [global]
            // [in.tproxy]
            // [out.socks]
            // name [value]
            var it = std.mem.tokenize(u8, line, " \t\r");

            const name = it.next() orelse continue;
            const value = it.next();

            if (it.next() != null)
                break :e "too many values";

            switch (name[0]) {
                '#' => continue,
                '[' => {
                    if (name[name.len - 1] != ']') {
                        break :e "invalid format";
                    } else if (std.mem.eql(u8, name, "[global]")) {
                        defines = &cfg_global.defines;
                    } else if (std.mem.startsWith(u8, name, "[in.")) {
                        const proto = name[4 .. name.len - 1];
                        defines = in.get_cfg_defines(proto) orelse break :e "unknown proto";
                    } else if (std.mem.startsWith(u8, name, "[out.")) {
                        const proto = name[5 .. name.len - 1];
                        defines = out.get_cfg_defines(proto) orelse break :e "unknown proto";
                    } else {
                        break :e "unknown section";
                    }
                },
                else => {
                    const def = get_def(defines, name) orelse
                        break :e "unknown config";
                    switch (def.value) {
                        .required => if (value == null) break :e "missing value",
                        .no_value => if (value != null) break :e "unexpected value",
                        .optional => {},
                    }
                    def.func(value);
                },
            }

            continue;
        };

        // error handling
        log.err(src, "'%s': %s: %.*s", .{ filename, err, cc.to_int(line.len), line.ptr });
        cc.exit(1);
    }
}
