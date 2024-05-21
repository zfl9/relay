const build_opts = @import("build_opts");
const cfg = @import("cfg.zig");

const modules = get_modules();

const all_modules = .{
    @import("in_tproxy.zig"),
    @import("in_socks.zig"),
    @import("in_tlsproxy.zig"),
};

fn get_modules() [cnt_modules()]type {
    var array: [cnt_modules()]type = undefined;
    var i = 0;
    for (all_modules) |module| {
        if (@field(build_opts, "enable_" ++ module.name)) {
            array[i] = module;
            i += 1;
        }
    }
    return array;
}

fn cnt_modules() comptime_int {
    var n = 0;
    for (all_modules) |module| {
        if (@field(build_opts, "enable_" ++ module.name))
            n += 1;
    }
    return n;
}

pub fn get_cfg_defines(proto: []const u8) ?[]const cfg.Define {
    _ = proto; // autofix
    return null;
}
