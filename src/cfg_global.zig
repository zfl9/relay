const cfg = @import("cfg.zig");

// zig fmt: on
pub const defines = [_]cfg.Define{
    .{ .name = "threads", .value = .required, .func = cfg_threads },
    .{ .name = "cert-verify", .value = .no_value, .func = cfg_cert_verify },
    .{ .name = "ca-certs", .value = .required, .func = cfg_ca_certs },
    .{ .name = "reuse-port", .value = .no_value, .func = cfg_reuse_port },
    .{ .name = "verbose", .value = .no_value, .func = cfg_verbose },
};
// zig fmt: on

fn cfg_threads(in_value: ?[]const u8) void {
    _ = in_value; // autofix
    // TODO
}

fn cfg_cert_verify(in_value: ?[]const u8) void {
    _ = in_value; // autofix
    // TODO
}

fn cfg_ca_certs(in_value: ?[]const u8) void {
    _ = in_value; // autofix
    // TODO
}

fn cfg_reuse_port(in_value: ?[]const u8) void {
    _ = in_value; // autofix
    // TODO
}

fn cfg_verbose(in_value: ?[]const u8) void {
    _ = in_value; // autofix
    // TODO
}
