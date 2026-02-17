const std = @import("std");
const nix_wasm_zig = @import("nix_wasm_zig");

const Value = nix_wasm_zig.Value;
const Attr = nix_wasm_zig.Attr.Entry;
const Type = nix_wasm_zig.Type;
const nixWarn = nix_wasm_zig.nixWarn;
const nixPanic = nix_wasm_zig.nixPanic;
const wasm_allocator = std.heap.wasm_allocator;

comptime {
    nix_wasm_zig.entrypoint(init);
}

fn init() void {
    nixWarn("json wasm module");
}

fn jsonToNix(allocator: std.mem.Allocator, json: *const std.json.Value) Value {
    return switch (json.*) {
        .null => Value.makeNull(),
        .bool => |b| Value.makeBool(b),
        .integer => |n| Value.makeInt(n),
        .float => |f| Value.makeFloat(f),
        .string, .number_string => |s| Value.makeString(s),
        .array => |arr| {
            const items = allocator.alloc(Value, arr.items.len) catch nixPanic("out of memory");
            defer allocator.free(items);

            for (arr.items, 0..) |item, i| {
                items[i] = jsonToNix(allocator, &item);
            }

            return Value.makeList(items);
        },
        .object => |obj| {
            const attrs = allocator.alloc(Attr, obj.count()) catch nixPanic("out of memory");
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
            const s = value.getString(allocator) catch nixPanic("failed to get string");
            defer allocator.free(s);
            try jw.write(s);
        },
        .Path => {
            const p = value.getPath(allocator) catch nixPanic("failed to get path");
            defer allocator.free(p);
            try jw.write(p);
        },
        .List => {
            const items = value.getList(allocator) catch nixPanic("failed to get list");
            defer allocator.free(items);

            try jw.beginArray();

            for (items) |item| {
                try nixToJson(allocator, jw, item);
            }

            try jw.endArray();
        },
        .Attrs => {
            var attrs = value.getAttrset(allocator) catch nixPanic("failed to get attrset");
            defer attrs.deinit();

            try jw.beginObject();

            var it = attrs.iterator();

            while (it.next()) |entry| {
                try jw.objectField(entry.key_ptr.*);
                try nixToJson(allocator, jw, entry.value_ptr.*);
            }

            try jw.endObject();
        },
        .Function => nixPanic("cannot convert a function to JSON"),
    }
}

/// fromJSON ''{"x": [1, 2, 3], "y": null}''
/// => { x = [ 1 2 3 ]; y = null; }
export fn fromJSON(arg: Value) Value {
    var arena = std.heap.ArenaAllocator.init(wasm_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const json_str = arg.getString(allocator) catch nixPanic("fromJSON: expected a string");

    const parsed = std.json.parseFromSliceLeaky(
        std.json.Value,
        allocator,
        json_str,
        .{},
    ) catch nixPanic("fromJSON: invalid JSON");

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

    nixToJson(allocator, &jw, arg) catch nixPanic("JSON write error");

    const result = writer.toOwnedSlice() catch nixPanic("toJSON: out of memory");
    return Value.makeString(result);
}
