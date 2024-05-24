const std = @import("std");
const c = @import("c.zig");
const cc = @import("cc.zig");
const g = @import("g.zig");
const in = @import("in.zig");
const out = @import("out.zig");
const Config = @import("Config.zig");
const log = @import("log.zig");
const str2int = @import("str2int.zig");
const flags_op = @import("flags_op.zig");
const assert = std.debug.assert;

const SectionType = enum { global, in, out };

fn load_config(start: [*]const u8, end: [*]const u8, section_type: SectionType, proto_name: []const u8) void {
    const section = start[0..cc.ptrdiff_u(u8, end, start)];
    switch (section_type) {
        .global => {
            g.config = Config.load(section) orelse cc.exit(1);
        },
        .in => {
            g.in_config = in.load_config(proto_name, section) orelse cc.exit(1);
        },
        .out => {
            g.out_config = out.load_config(proto_name, section) orelse cc.exit(1);
        },
    }
}

pub fn load(filename: cc.ConstStr) void {
    const src = @src();

    const mem = cc.mmap_file(filename) orelse {
        log.err(src, "failed to open file: '%s' (%m)", .{filename});
        cc.exit(1);
    };
    defer _ = cc.munmap(mem);

    const Loaded = enum(u8) {
        global = 1 << 0,
        in = 1 << 1,
        out = 1 << 2,
        _,
        pub usingnamespace flags_op.get(@This());
    };
    var loaded: Loaded = Loaded.empty();
    defer {
        if (!loaded.has_all(.{ .in, .out })) {
            const missing = cc.b2s(!loaded.has(.in), "in", "out");
            log.err(src, "missing %s.proto config", .{missing});
            cc.exit(1);
        }
        if (!loaded.has(.global))
            g.config = Config.load("").?;
    }

    var section_start: ?[*]const u8 = null; // the start pos of the content
    var section_type: SectionType = undefined;
    var proto_name: []const u8 = undefined; // in or out
    defer if (section_start) |start|
        load_config(start, mem.ptr + mem.len, section_type, proto_name);

    var line_it = std.mem.tokenize(u8, mem, "\r\n");
    while (line_it.next()) |line| {
        const err: cc.ConstStr = e: {
            var it = std.mem.tokenize(u8, line, " \t");

            // # comments
            // [global] # comments
            // [in.tproxy]
            // [out.socks]
            // name = value # comments
            // name = "string"
            const token = it.next() orelse continue;

            switch (token[0]) {
                '#' => continue,

                '[' => {
                    if (token[token.len - 1] != ']')
                        break :e "invalid format";

                    const rest = it.rest();
                    if (rest.len > 0 and rest[0] != '#')
                        break :e "invalid format";

                    // handle the last section
                    if (section_start) |start|
                        load_config(start, token.ptr, section_type, proto_name);

                    // advance to the next section
                    section_start = token.ptr + token.len;
                    if (std.mem.eql(u8, token, "[global]")) {
                        section_type = .global;
                        proto_name = undefined;
                        if (loaded.has(.global)) break :e "duplicate global section";
                        loaded.add(.global);
                    } else if (std.mem.startsWith(u8, token, "[in.")) {
                        section_type = .in;
                        proto_name = token[4 .. token.len - 1];
                        if (loaded.has(.in)) break :e "duplicate in.proto section";
                        loaded.add(.in);
                    } else if (std.mem.startsWith(u8, token, "[out.")) {
                        section_type = .out;
                        proto_name = token[5 .. token.len - 1];
                        if (loaded.has(.out)) break :e "duplicate out.proto section";
                        loaded.add(.out);
                    } else {
                        break :e "unknown section";
                    }
                },

                else => if (section_start == null) break :e "out of section",
            }

            continue;
        };

        // error handling
        log.err(src, "'%s': %s: %.*s", .{ filename, err, cc.to_int(line.len), line.ptr });
        cc.exit(1);
    }
}
