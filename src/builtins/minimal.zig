// Minimal reference plugin
const std = @import("std");
const nix_wasm_zig = @import("nix_wasm_zig");

const Nix = nix_wasm_zig.Nix;
const Value = Nix.Value;

// logging (allows use of @panic in Zig which just calls Nix's throw)
pub const panic = nix_wasm_zig.panic;
const warn = nix_wasm_zig.warn;

// if you need an allocator, highly recommend using std.heap.ArenaAllocator with this
const wasm_allocator = std.heap.wasm_allocator;

// exports nix_wasm_init_v1()
comptime {
    nix_wasm_zig.entrypoint(init);
}

// custom init code can be written here
fn init() void {
    warn("minimal wasm module");
}

// 'export' exposes this function to be called using builtins.wasm ./path/to/builtin.wasm "example" "Hello, World!"
//
// 'arg' can be any valid Value, 'arg' would denote just one simple parameter, while 'args' implies an attrset for multiple arguments
// the Value returned can be any value except functions
export fn example(arg: Value) Value {
    return arg;
}
