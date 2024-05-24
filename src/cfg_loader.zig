const std = @import("std");
const cc = @import("cc.zig");
const g = @import("g.zig");
const log = @import("log.zig");
const str2int = @import("str2int.zig");
const SourceLocation = std.builtin.SourceLocation;
const assert = std.debug.assert;

pub const EMPTY_STR = &[0:0]u8{};

/// ```zig
/// Config = struct {
///     ip: [][:0]const u8 = &.{},
///     port: u16 = 1080,
///     udp: bool = true,
/// }
/// content = \\ ip = 127.0.0.1 # foo
///           \\ ip = 192.168.1.1 # bar
///           \\ port = 1080
///           \\ udp = true
///           \\ # comments
/// ```
pub fn load(comptime src: SourceLocation, config: anytype, content: []const u8) ?void {
    const ptrinfo = @typeInfo(@TypeOf(config));
    if (ptrinfo != .Pointer or @typeInfo(ptrinfo.Pointer.child) != .Struct)
        @compileError("expect struct pointer, got " ++ @typeName(@TypeOf(config)));
    const Config = ptrinfo.Pointer.child;

    var line_it = std.mem.tokenize(u8, content, "\r\n");
    while (line_it.next()) |raw_line| {
        const err: cc.ConstStr = e: {
            const line = trim_space(raw_line);
            if (line[0] == '#') continue;

            const sep = std.mem.indexOfScalar(u8, line, '=') orelse break :e "invalid format";
            const name = trim_space(line[0..sep]);
            const value = trim_space(trim_comment(line[sep + 1 ..]));
            if (value.len == 0) break :e "missing value";

            if (load_field(Config, config, name, value)) |err|
                break :e err;

            continue;
        };

        log.err(src, "%s: '%.*s'", .{ err, cc.to_int(raw_line.len), raw_line.ptr });
        return null;
    }
}

fn trim_space(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t");
}

fn trim_comment(s: []const u8) []const u8 {
    const end = std.mem.indexOf(u8, s, " #") orelse
        std.mem.indexOf(u8, s, "\t#") orelse s.len;
    return s[0..end];
}

/// return error msg if failed
/// https://github.com/ziglang/zig/issues/11369
fn load_field(comptime Config: type, config: *Config, name: []const u8, value: []const u8) ?cc.ConstStr {
    inline for (std.meta.fields(Config)) |field| {
        if (std.mem.eql(u8, field.name, name)) {
            const p_field = &@field(config, field.name);
            p_field.* = parse(Config, field, p_field.*, value) orelse return "invalid value";
            return null; // no error
        }
    }
    return "unknown config";
}

/// return new value (or null if failed)
fn parse(
    comptime Config: type,
    comptime field: std.builtin.Type.StructField,
    old_value: field.field_type,
    cfg_value: []const u8,
) ?field.field_type {
    assert(cfg_value.len > 0);

    const field_name = @typeName(Config) ++ "." ++ field.name;
    const field_type = field.field_type;
    const field_typename = @typeName(field_type);
    const p_default_value = field.default_value orelse
        @compileError("field must have default value: " ++ field_name);

    return switch (@typeInfo(field_type)) {
        .Bool => parse_bool(cfg_value),

        .Int => parse_int(field_type, cfg_value),

        .Pointer => |info| b: {
            if (info.size != .Slice)
                @compileError("non-slice pointer not supported: " ++ field_typename ++ ", field: " ++ field_name);

            // check the length of the slice object
            const slice_len = @ptrCast(*const []u8, p_default_value).len;
            if (slice_len != 0)
                @compileError("the default value of the dyn-alloc field must be empty: " ++ field_name ++ ", len: " ++ cc.comptime_tostr(slice_len));

            if (info.sentinel) |p_sentinel| {
                // string: [:0]u8, [:0]const u8
                if (info.child != u8)
                    @compileError("sentinel-terminated slice not supported: " ++ field_typename ++ ", field: " ++ field_name);

                if (@ptrCast(*const u8, p_sentinel).* != 0)
                    @compileError("string field must end with sentinel 0: " ++ field_typename ++ ", field: " ++ field_name);

                break :b parse_str(old_value, cfg_value);
            } else {
                // slice/array: []T, []const T
                break :b parse_into_slice(info.child, old_value, cfg_value);
            }
        },

        else => @compileError("expect {bool, int, string, and their slice}, got " ++ field_typename ++ ", field: " ++ field_name),
    };
}

fn parse_bool(cfg_value: []const u8) ?bool {
    if (std.mem.eql(u8, cfg_value, "true"))
        return true;
    if (std.mem.eql(u8, cfg_value, "false"))
        return false;
    return null;
}

fn parse_int(comptime T: type, cfg_value: []const u8) ?T {
    return str2int.parse(T, cfg_value, 10);
}

fn parse_str(in_old_str: [:0]const u8, cfg_value: []const u8) ?[:0]u8 {
    const old_str = cc.remove_const(in_old_str);
    assert(cfg_value.len > 0);

    // replace old content
    const new_str = if (old_str.len > 0 and g.allocator.resize(old_str.ptr[0 .. old_str.len + 1], cfg_value.len + 1) != null)
        old_str.ptr[0 .. cfg_value.len + 1]
    else b: {
        if (old_str.len > 0) g.allocator.free(old_str);
        break :b g.allocator.alloc(u8, cfg_value.len + 1) catch unreachable;
    };

    @memcpy(new_str.ptr, cfg_value.ptr, cfg_value.len);
    new_str[cfg_value.len] = 0;

    return new_str[0..cfg_value.len :0];
}

/// ignore duplicate elements (so it's actually a hashset)
fn parse_into_slice(comptime T: type, old_slice: []const T, cfg_value: []const u8) ?[]T {
    comptime var is_string = false;

    const value_to_add = (switch (@typeInfo(T)) {
        .Bool => parse_bool(cfg_value),
        .Int => parse_int(T, cfg_value),
        .Pointer => b: {
            // string
            if (T != [:0]const u8 and T != [:0]u8)
                @compileError("expect {bool, int, string}, got " ++ @typeName(T));
            is_string = true;
            break :b @as(?[]const u8, cfg_value);
        },
        else => @compileError("expect {bool, int, string}, got " ++ @typeName(T)),
    }) orelse return null;

    // check for duplicate
    for (old_slice) |value| {
        if (is_string) {
            if (std.mem.eql(u8, value_to_add, value))
                return cc.remove_const(old_slice);
        } else {
            if (value_to_add == value)
                return cc.remove_const(old_slice);
        }
    }

    const new_slice = if (old_slice.len == 0)
        g.allocator.alloc(T, 1) catch unreachable
    else
        g.allocator.realloc(cc.remove_const(old_slice), old_slice.len + 1) catch unreachable;

    new_slice[old_slice.len] = if (is_string)
        (g.allocator.dupeZ(u8, value_to_add) catch unreachable)
    else
        value_to_add;

    return new_slice;
}
