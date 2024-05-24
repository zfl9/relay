const cfg_loader = @import("cfg_loader.zig");
const cfg_checker = @import("cfg_checker.zig");

const Config = @This();

ca_certs: [:0]u8 = "",
cert_verify: bool = false,
reuse_port: bool = false,
verbose: bool = false,
threads: u8 = 1,

pub fn load(content: []const u8) ?Config {
    var self = Config{};
    const src = @src();
    cfg_loader.load(src, &self, content) orelse return null;
    return self;
}
