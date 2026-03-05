const std = @import("std");
const nix_wasm_zig = @import("nix_wasm_zig");

const Nix = nix_wasm_zig.Nix;
const Value = Nix.Value;
pub const panic = nix_wasm_zig.panic;

pub fn main() !noreturn {
    var arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const arg = try Value.getWasiArg();

    std.debug.print("Hello, {s}!\n", .{arg.getString(allocator)});

    Value.makeNull().returnToNix();
}
