const std = @import("std");
const nix_wasm_zig = @import("nix_wasm_zig");

const Nix = nix_wasm_zig.Nix;
const Value = Nix.Value;
const warn = nix_wasm_zig.warn;
const wasm_allocator = std.heap.wasm_allocator;

comptime {
    nix_wasm_zig.entrypoint(init);
}

fn init() void {
    warn("base64 wasm module");
}

/// base64enc "nix"
/// => "bml4"
export fn base64enc(arg: Value) Value {
    var arena = std.heap.ArenaAllocator.init(wasm_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = arg.getString(allocator) catch @panic("expected a string");

    const encoded = std.base64.standard.Encoder.encode(
        allocator.alloc(u8, std.base64.standard.Encoder.calcSize(input.len)) catch @panic("out of memory"),
        input,
    );

    return Value.makeString(encoded);
}

/// base64dec "bml4"
/// => "nix"
export fn base64dec(arg: Value) Value {
    var arena = std.heap.ArenaAllocator.init(wasm_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = arg.getString(allocator) catch @panic("expected a string");

    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(input) catch @panic("invalid base64 input");
    const buf = allocator.alloc(u8, decoded_len) catch @panic("out of memory");

    std.base64.standard.Decoder.decode(buf, input) catch @panic("invalid base64 input");

    return Value.makeString(buf);
}
