const std = @import("std");
const nix_wasm_zig = @import("nix_wasm_zig");

const Nix = nix_wasm_zig.Nix;
const Value = Nix.Value;
pub const panic = nix_wasm_zig.panic;

export fn _start() noreturn {
    std.debug.print("Hello, world!", .{});
    Value.makeNull().returnToNix();
}