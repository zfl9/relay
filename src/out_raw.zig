const cfg_loader = @import("cfg_loader.zig");
const cfg_checker = @import("cfg_checker.zig");

pub const NAME = "raw";

pub const Config = struct {
    pub fn load(content: []const u8) ?Config {
        var self = Config{};
        const src = @src();
        cfg_loader.load(src, &self, content) orelse return null;
        return self;
    }
};
