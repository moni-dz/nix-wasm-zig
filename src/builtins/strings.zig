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
    warn("strings wasm module");
}

fn validateStringList(items: []const Value) void {
    for (items) |item| {
        switch (item.getType()) {
            .String => {},
            else => @panic("Expected a list of strings"),
        }
    }
}

fn concatWithSeparator(allocator: std.mem.Allocator, sep: []const u8, strings: []const Value, trailing: bool) std.mem.Allocator.Error!Value {
    var total_len: usize = 0;
    const str_slices = try allocator.alloc([]const u8, strings.len);

    defer {
        for (str_slices) |s| allocator.free(s);
        allocator.free(str_slices);
    }

    for (strings, 0..) |s, i| {
        str_slices[i] = s.getString(allocator) catch @panic("failed to get string");
        total_len += str_slices[i].len;
    }

    if (strings.len > 1) {
        total_len += sep.len * (strings.len - 1);
    }

    if (trailing) {
        total_len += sep.len;
    }

    const result = try allocator.alloc(u8, total_len);

    var pos: usize = 0;

    for (str_slices, 0..) |s, i| {
        if (i > 0) {
            @memcpy(result[pos..][0..sep.len], sep);
            pos += sep.len;
        }

        @memcpy(result[pos..][0..s.len], s);
        pos += s.len;
    }

    if (trailing) {
        @memcpy(result[pos..][0..sep.len], sep);
    }

    return Value.makeString(result);
}

fn replaceStringsImpl(allocator: std.mem.Allocator, input: []const u8, from: []const Value, to: []const Value) std.mem.Allocator.Error!Value {
    if (from.len == 0 and to.len == 0) {
        return Value.makeString(input);
    }

    if (from.len != to.len) {
        @panic("from and to lists must have the same length");
    }

    validateStringList(from);
    validateStringList(to);

    const from_strs = try allocator.alloc([]const u8, from.len);

    defer {
        for (from_strs) |s| allocator.free(s);
        allocator.free(from_strs);
    }

    for (from, 0..) |v, i| {
        from_strs[i] = v.getString(allocator) catch @panic("failed to get string");
    }

    const to_strs = try allocator.alloc([]const u8, to.len);

    defer {
        for (to_strs) |s| allocator.free(s);
        allocator.free(to_strs);
    }

    for (to, 0..) |v, i| {
        to_strs[i] = v.getString(allocator) catch @panic("failed to get string");
    }

    var result: std.ArrayListUnmanaged(u8) = .{};
    try result.ensureTotalCapacity(allocator, input.len);

    var pos: usize = 0;
    var unmatched_start: usize = 0;

    while (pos <= input.len) {
        var matched = false;

        for (from_strs, to_strs) |f, t| {
            if (f.len > 0 and pos + f.len <= input.len and std.mem.eql(u8, input[pos..][0..f.len], f)) {
                if (unmatched_start < pos) {
                    try result.appendSlice(allocator, input[unmatched_start..pos]);
                }

                try result.appendSlice(allocator, t);
                pos += f.len;
                unmatched_start = pos;
                matched = true;
                break;
            } else if (f.len == 0) {
                if (unmatched_start < pos) {
                    try result.appendSlice(allocator, input[unmatched_start..pos]);
                }

                try result.appendSlice(allocator, t);

                if (pos < input.len) {
                    try result.appendSlice(allocator, input[pos..][0..1]);
                }

                pos += 1;
                unmatched_start = pos;
                matched = true;
                break;
            }
        }

        if (!matched) {
            if (pos < input.len) {
                pos += 1;
            } else {
                break;
            }
        }
    }

    if (unmatched_start < pos) {
        try result.appendSlice(allocator, input[unmatched_start..pos]);
    }

    return Value.makeString(try result.toOwnedSlice(allocator));
}

/// concatStringsSep { sep = "/"; list = ["usr" "local" "bin"]; }
/// => "usr/local/bin"
export fn concatStringsSep(args: Value) Value {
    var arena = std.heap.ArenaAllocator.init(wasm_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sep_val = args.getAttr("sep") orelse @panic("missing 'sep' argument");
    const sep = sep_val.getString(allocator) catch @panic("failed to get sep string");

    const list_val = args.getAttr("list") orelse @panic("missing 'list' argument");
    const list = list_val.getList(allocator) catch @panic("failed to get list");

    validateStringList(list);

    return concatWithSeparator(allocator, sep, list, false) catch @panic("out of memory");
}

/// concatStrings ["foo" "bar"]
/// => "foobar"
export fn concatStrings(arg: Value) Value {
    var arena = std.heap.ArenaAllocator.init(wasm_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const list = arg.getList(allocator) catch @panic("Expected a list of strings");
    validateStringList(list);

    return concatWithSeparator(allocator, "", list, false) catch @panic("out of memory");
}

/// join { sep = ", "; list = ["foo" "bar"]; }
/// => "foo, bar"
export fn join(args: Value) Value {
    return concatStringsSep(args);
}

/// concatLines [ "foo" "bar" ]
/// => "foo\nbar\n"
export fn concatLines(arg: Value) Value {
    var arena = std.heap.ArenaAllocator.init(wasm_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const list = arg.getList(allocator) catch @panic("failed to get list");
    validateStringList(list);

    return concatWithSeparator(allocator, "\n", list, true) catch @panic("out of memory");
}

/// replaceStrings { from = ["Hello" "world"]; to = ["Goodbye" "Nix"]; s = "Hello, world!"; }
/// => "Goodbye, Nix!"
export fn replaceStrings(args: Value) Value {
    var arena = std.heap.ArenaAllocator.init(wasm_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const from_val = args.getAttr("from") orelse @panic("missing 'from' argument");
    const from = from_val.getList(allocator) catch @panic("failed to get from list");

    const to_val = args.getAttr("to") orelse @panic("missing 'to' argument");
    const to = to_val.getList(allocator) catch @panic("failed to get to list");

    const s_val = args.getAttr("s") orelse @panic("missing 's' argument");
    const input = s_val.getString(allocator) catch @panic("failed to get input string");

    return replaceStringsImpl(allocator, input, from, to) catch @panic("out of memory");
}

/// intersperse { sep = "/"; list = ["usr" "local" "bin"]; }
/// => ["usr" "/" "local" "/" "bin"]
export fn intersperse(args: Value) Value {
    var arena = std.heap.ArenaAllocator.init(wasm_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const sep_val = args.getAttr("sep") orelse @panic("missing 'sep' argument");
    const sep = sep_val.getString(allocator) catch @panic("failed to get sep string");

    const list_val = args.getAttr("list") orelse @panic("missing 'list' argument");
    const strings = list_val.getList(allocator) catch @panic("failed to get list");

    validateStringList(strings);

    if (strings.len == 0) {
        return Value.makeList(&.{});
    }

    const result_len = strings.len * 2 - 1;
    const result = allocator.alloc(Value, result_len) catch @panic("out of memory");

    const sep_value = Value.makeString(sep);

    for (strings, 0..) |string, i| {
        if (i > 0) {
            result[i * 2 - 1] = sep_value;
        }

        result[i * 2] = string;
    }

    return Value.makeList(result);
}

/// replicate { n = 3; s = "v"; }
/// => "vvv"
export fn replicate(args: Value) Value {
    var arena = std.heap.ArenaAllocator.init(wasm_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const n_val = args.getAttr("n") orelse @panic("missing 'n' argument");
    const n = n_val.getInt();

    if (n < 0) {
        @panic("'n' must be a non-negative integer");
    }

    const s_val = args.getAttr("s") orelse @panic("missing 's' argument");
    const s = s_val.getString(allocator) catch @panic("failed to get string");

    const count: usize = @intCast(n);
    const result = allocator.alloc(u8, s.len * count) catch @panic("out of memory");

    for (0..count) |i| {
        @memcpy(result[i * s.len ..][0..s.len], s);
    }

    return Value.makeString(result);
}
