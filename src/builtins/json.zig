const std = @import("std");
const nix_wasm_zig = @import("nix_wasm_zig");

const Nix = nix_wasm_zig.Nix;
const Value = Nix.Value;
const Attr = Nix.Attr.Entry;
const Type = Nix.Type;

pub const panic = nix_wasm_zig.panic;
const warn = nix_wasm_zig.warn;

const wasm_allocator = std.heap.wasm_allocator;

comptime {
    nix_wasm_zig.entrypoint(init);
}

fn init() void {
    warn("json wasm module");
}

fn jsonToNix(allocator: std.mem.Allocator, json: *const std.json.Value) Value {
    return switch (json.*) {
        .null => Value.makeNull(),
        .bool => |b| Value.makeBool(b),
        .integer => |n| Value.makeInt(n),
        .float => |f| Value.makeFloat(f),
        .string, .number_string => |s| Value.makeString(s),
        .array => |arr| {
            const items = allocator.alloc(Value, arr.items.len) catch @panic("out of memory");
            defer allocator.free(items);

            for (arr.items, 0..) |item, i| {
                items[i] = jsonToNix(allocator, &item);
            }

            return Value.makeList(items);
        },
        .object => |obj| {
            const attrs = allocator.alloc(Attr, obj.count()) catch @panic("out of memory");
            defer allocator.free(attrs);

            var it = obj.iterator();
            var i: usize = 0;

            while (it.next()) |entry| : (i += 1) {
                attrs[i] = .{
                    .name = entry.key_ptr.*,
                    .value = jsonToNix(allocator, entry.value_ptr),
                };
            }

            return Value.makeAttrset(allocator, attrs);
        },
    };
}

fn nixToJson(allocator: std.mem.Allocator, jw: *std.json.Stringify, value: Value) std.json.Stringify.Error!void {
    switch (value.getType()) {
        .Null => try jw.write(null),
        .Bool => try jw.write(value.getBool()),
        .Int => try jw.write(value.getInt()),
        .Float => try jw.write(value.getFloat()),
        .String => {
            const s = value.getString(allocator) catch @panic("failed to get string");
            defer allocator.free(s);
            try jw.write(s);
        },
        .Path => {
            const p = value.getPath(allocator) catch @panic("failed to get path");
            defer allocator.free(p);
            try jw.write(p);
        },
        .List => {
            const items = value.getList(allocator) catch @panic("failed to get list");
            defer allocator.free(items);

            try jw.beginArray();

            for (items) |item| {
                try nixToJson(allocator, jw, item);
            }

            try jw.endArray();
        },
        .Attrs => {
            var attrs = value.getAttrset(allocator) catch @panic("failed to get attrset");
            defer attrs.deinit();

            try jw.beginObject();

            var it = attrs.iterator();

            while (it.next()) |entry| {
                try jw.objectField(entry.key_ptr.*);
                try nixToJson(allocator, jw, entry.value_ptr.*);
            }

            try jw.endObject();
        },
        .Function => @panic("cannot convert a function to JSON"),
    }
}

/// fromJSON ''{"x": [1, 2, 3], "y": null}''
/// => { x = [ 1 2 3 ]; y = null; }
export fn fromJSON(arg: Value) Value {
    var arena = std.heap.ArenaAllocator.init(wasm_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const json_str = arg.getString(allocator) catch @panic("fromJSON: expected a string");

    const parsed = std.json.parseFromSliceLeaky(
        std.json.Value,
        allocator,
        json_str,
        .{},
    ) catch @panic("fromJSON: invalid JSON");

    return jsonToNix(allocator, &parsed);
}

/// toJSON { x = [ 1 2 3 ]; y = null; }
/// => {"x": [1, 2, 3], "y": null}
export fn toJSON(arg: Value) Value {
    var arena = std.heap.ArenaAllocator.init(wasm_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var writer: std.Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();

    var jw: std.json.Stringify = .{
        .writer = &writer.writer,
        .options = .{},
    };

    nixToJson(allocator, &jw, arg) catch @panic("JSON write error");

    const result = writer.toOwnedSlice() catch @panic("toJSON: out of memory");
    return Value.makeString(result);
}
