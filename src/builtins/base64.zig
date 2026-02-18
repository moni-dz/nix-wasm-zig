const std = @import("std");
const nix_wasm_zig = @import("nix_wasm_zig");

const Value = nix_wasm_zig.Value;
const nixWarn = nix_wasm_zig.nixWarn;
const nixPanic = nix_wasm_zig.nixPanic;
const wasm_allocator = std.heap.wasm_allocator;

comptime {
    nix_wasm_zig.entrypoint(init);
}

fn init() void {
    nixWarn("base64 wasm module");
}

export fn base64enc(arg: Value) Value {
    var arena = std.heap.ArenaAllocator.init(wasm_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = arg.getString(allocator) catch nixPanic("expected a string");

    const encoded = std.base64.standard.Encoder.encode(
        allocator.alloc(u8, std.base64.standard.Encoder.calcSize(input.len)) catch nixPanic("out of memory"),
        input,
    );

    return Value.makeString(encoded);
}

export fn base64dec(arg: Value) Value {
    var arena = std.heap.ArenaAllocator.init(wasm_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = arg.getString(allocator) catch nixPanic("expected a string");

    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(input) catch nixPanic("invalid base64 input");
    const buf = allocator.alloc(u8, decoded_len) catch nixPanic("out of memory");

    std.base64.standard.Decoder.decode(buf, input) catch nixPanic("invalid base64 input");

    return Value.makeString(buf);
}
