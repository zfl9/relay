const cfg_loader = @import("cfg_loader.zig");
const cfg_checker = @import("cfg_checker.zig");

pub const NAME = "trojan";

pub const Config = struct {
    passwd: [:0]const u8 = "",
    server: [:0]const u8 = "",
    port: u16 = 443,
    tcp: bool = true,
    udp: bool = true,

    pub fn load(content: []const u8) ?Config {
        var self = Config{};
        const src = @src();
        cfg_loader.load(src, &self, content) orelse return null;
        cfg_checker.required_str(src, self.passwd, "passwd") orelse return null;
        cfg_checker.required_str(src, self.server, "server") orelse return null;
        cfg_checker.check_port(src, self.port) orelse return null;
        cfg_checker.check_tcp_udp(src, self.tcp, self.udp) orelse return null;
        return self;
    }
};
