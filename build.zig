const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const nix_wasm_zig = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const builtins_dir = b.build_root.handle.openDir("src/builtins", .{ .iterate = true }) catch @panic("failed to open src/builtins");

    var iter = builtins_dir.iterate();

    while (iter.next() catch @panic("failed to iterate src/builtins")) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".zig"))
            continue;

        const name = entry.name[0 .. entry.name.len - ".zig".len];

        const exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("src/builtins/{s}", .{entry.name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "nix_wasm_zig", .module = nix_wasm_zig },
                },
            }),
        });

        exe.entry = .disabled;
        exe.rdynamic = true;

        b.installArtifact(exe);
    }
}
