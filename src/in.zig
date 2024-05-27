const std = @import("std");
const build_opts = @import("build_opts");
const cfg = @import("cfg.zig");
const log = @import("log.zig");
const cc = @import("cc.zig");
const g = @import("g.zig");

const modules = b: {
    const s = struct {
        const all_modules = .{
            @import("in_tproxy.zig"),
            @import("in_socks.zig"),
            @import("in_tlsproxy.zig"),
            @import("in_trojan.zig"),
        };
        fn is_enable(comptime mod: type) bool {
            return @field(build_opts, "in_" ++ mod.NAME);
        }
        fn len() comptime_int {
            var n = 0;
            for (all_modules) |mod| {
                if (is_enable(mod))
                    n += 1;
            }
            return n;
        }
        fn fill(comptime list: []type) void {
            var n = 0;
            for (all_modules) |mod| {
                if (is_enable(mod)) {
                    list[n] = mod;
                    n += 1;
                }
            }
        }
    };
    var array: [s.len()]type = undefined;
    s.fill(&array);
    break :b array;
};

pub const Config = b: {
    var enum_fields: [modules.len]std.builtin.Type.EnumField = undefined;
    var union_fields: [modules.len]std.builtin.Type.UnionField = undefined;
    var n = 0;
    for (modules) |mod| {
        enum_fields[n] = .{
            .name = mod.NAME,
            .value = n,
        };
        union_fields[n] = .{
            .name = mod.NAME,
            .field_type = mod.Config,
            .alignment = @alignOf(mod.Config),
        };
        n += 1;
    }
    break :b @Type(.{ .Union = .{
        .layout = .Auto,
        .fields = union_fields[0..n],
        .decls = &.{},
        .tag_type = @Type(.{ .Enum = .{
            .layout = .Auto,
            .tag_type = u8,
            .fields = enum_fields[0..n],
            .decls = &.{},
            .is_exhaustive = true,
        } }),
    } });
};

pub fn load_config(proto_name: []const u8, content: []const u8) ?Config {
    inline for (modules) |mod| {
        if (std.mem.eql(u8, proto_name, mod.NAME)) {
            return @unionInit(
                Config,
                mod.NAME,
                mod.Config.load(content) orelse return null,
            );
        }
    }
    log.err(@src(), "unknown proto: %.*s", .{ cc.to_int(proto_name.len), proto_name.ptr });
    return null;
}
