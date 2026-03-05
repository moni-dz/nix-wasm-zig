const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});

    const freestanding_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const wasi_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });

    const subdirs: []const struct { dir: []const u8, target: std.Build.ResolvedTarget } = &.{
        .{ .dir = "freestanding", .target = freestanding_target },
        .{ .dir = "wasi", .target = wasi_target },
    };

    for (subdirs) |subdir| {
        const nix_wasm_zig = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = subdir.target,
            .optimize = optimize,
        });

        const builtins_dir = b.build_root.handle.openDir(
            b.fmt("src/builtins/{s}", .{subdir.dir}),
            .{ .iterate = true },
        ) catch |err| {
            std.log.err("failed to open src/builtins/{s}: {}", .{ subdir.dir, err });
            return error.BuildFailed;
        };

        var iter = builtins_dir.iterate();

        while (iter.next() catch |err| {
            std.log.err("failed to iterate src/builtins/{s}: {}", .{ subdir.dir, err });
            return error.BuildFailed;
        }) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".zig"))
                continue;

            const name = entry.name[0 .. entry.name.len - ".zig".len];

            const exe = b.addExecutable(.{
                .name = name,
                .root_module = b.createModule(.{
                    .root_source_file = b.path(b.fmt("src/builtins/{s}/{s}", .{ subdir.dir, entry.name })),
                    .target = subdir.target,
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
}
