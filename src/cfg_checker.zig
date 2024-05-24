const std = @import("std");
const cc = @import("cc.zig");
const log = @import("log.zig");
const SourceLocation = std.builtin.SourceLocation;

pub fn required_str(comptime src: SourceLocation, str: [:0]const u8, name: cc.ConstStr) ?void {
    if (str.len == 0) {
        log.err(src, "missing config: '%s'", .{name});
        return null;
    }
}

pub fn check_ip(comptime src: SourceLocation, ip: [:0]const u8) ?void {
    if (cc.ip_family(ip) == null) {
        log.err(src, "invalid ip: '%s'", .{ip.ptr});
        return null;
    }
}

pub fn check_ips(comptime src: SourceLocation, ips: []const [:0]const u8) ?void {
    for (ips) |ip|
        check_ip(src, ip) orelse return null;
}

pub fn check_port(comptime src: SourceLocation, port: u16) ?void {
    if (port == 0) {
        log.err(src, "invalid port: %u", .{cc.to_uint(port)});
        return null;
    }
}

pub fn check_tcp_udp(comptime src: SourceLocation, tcp: bool, udp: bool) ?void {
    if (!tcp and !udp) {
        log.err(src, "both tcp and udp are disabled", .{});
        return null;
    }
}
