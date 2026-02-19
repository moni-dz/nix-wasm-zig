//! Zig implementation for WASM support in Determinate Nix
//! https://github.com/DeterminateSystems/nix-src/blob/main/doc/manual/source/protocols/wasm.md
const std = @import("std");
const Allocator = std.mem.Allocator;

const log_extern = struct {
    extern fn panic(ptr: [*]const u8, len: usize) noreturn;
    extern fn warn(ptr: [*]const u8, len: usize) void;
};

extern fn get_type(value: Nix.Value.Id) Nix.Type;
extern fn make_int(value: i64) Nix.Value;
extern fn get_int(value: Nix.Value.Id) i64;
extern fn make_float(value: f64) Nix.Value;
extern fn get_float(value: Nix.Value.Id) f64;
extern fn make_string(ptr: [*]const u8, len: usize) Nix.Value;
extern fn copy_string(value: Nix.Value.Id, ptr: [*]u8, max_len: usize) usize;
extern fn make_path(base: Nix.Value.Id, ptr: [*]const u8, len: usize) Nix.Value;
extern fn copy_path(value: Nix.Value.Id, ptr: [*]u8, max_len: usize) usize;
extern fn make_bool(b: i32) Nix.Value;
extern fn get_bool(value: Nix.Value.Id) i32;
extern fn make_null() Nix.Value;
extern fn make_list(ptr: [*]const Nix.Value, len: usize) Nix.Value;
extern fn copy_list(value: Nix.Value.Id, ptr: [*]Nix.Value, max_len: usize) usize;
extern fn make_attrset(ptr: [*]const Nix.Attr.Input, len: usize) Nix.Value;
extern fn copy_attrset(value: Nix.Value.Id, ptr: [*]Nix.Attr.Output, max_len: usize) usize;
extern fn copy_attrname(value: Nix.Value.Id, attr_idx: usize, ptr: [*]u8, len: usize) void;
extern fn get_attr(value: Nix.Value.Id, ptr: [*]const u8, len: usize) Nix.Value.Id;
extern fn call_function(fun: Nix.Value.Id, ptr: [*]const Nix.Value, len: usize) Nix.Value;
extern fn make_app(fun: Nix.Value.Id, ptr: [*]const Nix.Value, len: usize) Nix.Value;
extern fn read_file(value: Nix.Value.Id, ptr: [*]u8, max_len: usize) usize;

pub fn warn(msg: []const u8) void {
    log_extern.warn(msg.ptr, msg.len);
}

fn panic_handler(msg: []const u8, _: ?usize) noreturn {
    log_extern.panic(msg.ptr, msg.len);
}

pub const panic = std.debug.FullPanic(panic_handler);

pub fn entrypoint(comptime moduleInit: ?fn () void) void {
    @export(&struct {
        fn nix_wasm_init_v1() callconv(.c) void {
            warn("hello from nix-wasm-zig");

            if (moduleInit) |init| {
                init();
            }
        }
    }.nix_wasm_init_v1, .{ .name = "nix_wasm_init_v1" });
}

pub const Nix = struct {
    pub const Type = enum(u32) {
        Int = 1,
        Float = 2,
        Bool = 3,
        String = 4,
        Path = 5,
        Null = 6,
        Attrs = 7,
        List = 8,
        Function = 9,
    };

    pub const Attr = struct {
        pub const Entry = struct { name: []const u8, value: Value };

        pub const Input = extern struct {
            name_ptr: u32,
            name_len: u32,
            value_id: Value.Id,
        };

        pub const Output = extern struct {
            value_id: Value.Id,
            name_len: u32,
        };
    };

    pub const Value = extern struct {
        pub const Id = u32;

        id: Id,

        pub fn getType(self: Value) Type {
            return get_type(self.id);
        }

        pub fn makeInt(n: i64) Value {
            return make_int(n);
        }

        pub fn getInt(self: Value) i64 {
            return get_int(self.id);
        }

        pub fn makeFloat(f: f64) Value {
            return make_float(f);
        }

        pub fn getFloat(self: Value) f64 {
            return get_float(self.id);
        }

        pub fn makeString(s: []const u8) Value {
            return make_string(s.ptr, s.len);
        }

        pub fn getString(self: Value, allocator: Allocator) []u8 {
            var buf: [256]u8 = undefined;
            const len = copy_string(self.id, &buf, buf.len);

            if (len > buf.len) {
                const larger_buf = allocator.alloc(u8, len) catch @panic("out of memory");

                const len2 = copy_string(self.id, larger_buf.ptr, larger_buf.len);
                std.debug.assert(len2 == len);

                return larger_buf;
            } else {
                const result = allocator.alloc(u8, len) catch @panic("out of memory");
                @memcpy(result, buf[0..len]);

                return result;
            }
        }

        pub fn makePath(self: Value, rel: []const u8) Value {
            return make_path(self.id, rel.ptr, rel.len);
        }

        pub fn getPath(self: Value, allocator: Allocator) []u8 {
            var buf: [256]u8 = undefined;
            const len = copy_path(self.id, &buf, buf.len);

            if (len > buf.len) {
                const larger_buf = allocator.alloc(u8, len) catch @panic("out of memory");

                const len2 = copy_path(self.id, larger_buf.ptr, larger_buf.len);
                std.debug.assert(len2 == len);

                return larger_buf;
            } else {
                const result = allocator.alloc(u8, len) catch @panic("out of memory");
                @memcpy(result, buf[0..len]);

                return result;
            }
        }

        pub fn makeBool(b: bool) Value {
            return make_bool(@intFromBool(b));
        }

        pub fn getBool(self: Value) bool {
            return get_bool(self.id) != 0;
        }

        pub fn makeNull() Value {
            return make_null();
        }

        pub fn makeList(list: []const Value) Value {
            return make_list(list.ptr, list.len);
        }

        pub fn getList(self: Value, allocator: Allocator) []Value {
            var buf: [64]Value = undefined;
            const len = copy_list(self.id, &buf, buf.len);

            if (len > buf.len) {
                const larger_buf = allocator.alloc(Value, len) catch @panic("out of memory");

                const len2 = copy_list(self.id, larger_buf.ptr, larger_buf.len);
                std.debug.assert(len2 == len);

                return larger_buf;
            } else {
                const result = allocator.alloc(Value, len) catch @panic("out of memory");
                @memcpy(result, buf[0..len]);
                return result;
            }
        }

        pub fn makeAttrset(allocator: Allocator, attrs: []const Attr.Entry) Value {
            const pairs = allocator.alloc(Attr.Input, attrs.len) catch @panic("out of memory");
            defer allocator.free(pairs);

            for (attrs, 0..) |attr, i| {
                pairs[i] = .{
                    .name_ptr = @intCast(@intFromPtr(attr.name.ptr)),
                    .name_len = @intCast(attr.name.len),
                    .value_id = attr.value.id,
                };
            }

            return make_attrset(pairs.ptr, pairs.len);
        }

        pub fn getAttrset(self: Value, allocator: Allocator) std.StringHashMap(Value) {
            var buf: [32]Attr.Output = undefined;
            const len = copy_attrset(self.id, &buf, buf.len);

            const attrs_buf: []Attr.Output = if (len > buf.len) blk: {
                const larger_buf = allocator.alloc(Attr.Output, len) catch @panic("out of memory");
                const len2 = copy_attrset(self.id, larger_buf.ptr, larger_buf.len);
                std.debug.assert(len2 == len);
                break :blk larger_buf;
            } else buf[0..len];

            defer if (len > buf.len) allocator.free(attrs_buf);

            var result = std.StringHashMap(Value).init(allocator);
            for (attrs_buf, 0..) |entry, attr_idx| {
                const name_buf = allocator.alloc(u8, entry.name_len) catch @panic("out of memory");
                copy_attrname(self.id, attr_idx, name_buf.ptr, entry.name_len);
                result.put(name_buf, .{ .id = entry.value_id }) catch @panic("out of memory");
            }

            return result;
        }

        pub fn getAttr(self: Value, attr_name: []const u8) ?Value {
            const value_id = get_attr(self.id, attr_name.ptr, attr_name.len);

            if (value_id == 0) {
                return null;
            }

            return .{ .id = value_id };
        }

        pub fn call(self: Value, args: []const Value) Value {
            return call_function(self.id, args.ptr, args.len);
        }

        pub fn lazyCall(self: Value, args: []const Value) Value {
            return make_app(self.id, args.ptr, args.len);
        }

        pub fn readFile(self: Value, allocator: Allocator) []u8 {
            var buf: [1024]u8 = undefined;
            const len = read_file(self.id, &buf, buf.len);

            if (len > buf.len) {
                const larger_buf = allocator.alloc(u8, len) catch @panic("out of memory");

                const len2 = read_file(self.id, larger_buf.ptr, larger_buf.len);
                std.debug.assert(len2 == len);

                return larger_buf;
            } else {
                const result = allocator.alloc(u8, len) catch @panic("out of memory");
                @memcpy(result, buf[0..len]);
                return result;
            }
        }
    };
};
