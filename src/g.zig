//! global variables

const std = @import("std");
const DynStr = @import("DynStr.zig");
const StrList = @import("StrList.zig");
const EvLoop = @import("EvLoop.zig");
const flags_op = @import("flags_op.zig");

pub const Flags = enum(u8) {
    verbose = 1 << 0,
    _,
    pub usingnamespace flags_op.get(Flags);
};

pub var flags: Flags = Flags.empty();

pub inline fn verbose() bool {
    return flags.has(.verbose);
}

pub var evloop: EvLoop = undefined;

/// global memory allocator
pub var allocator: std.mem.Allocator = undefined;

pub var cert_verify: bool = false;

/// the location of CA certs
pub var ca_certs: DynStr = .{};
