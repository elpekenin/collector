const std = @import("std");

pub fn build(b: *std.Build) void {
    // options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // configuration
    const llvm = if (optimize == .Debug)
        true // allow debugging with vanilla LLDB (avoid self-hosted backend)
    else
        null; // else, let zig take decissions for us

    // deps
    const dep_args = .{
        .target = target,
        .optimize = optimize,
    };

    const ptz = b.dependency("ptz", dep_args);
    const vaxis = b.dependency("vaxis", dep_args);
    const zqlite = b.dependency("zqlite", dep_args);

    // exe
    const exe = b.addExecutable(.{
        .name = "collector",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ptz", .module = ptz.module("ptz") },
                .{ .name = "vaxis", .module = vaxis.module("vaxis") },
                .{ .name = "zqlite", .module = zqlite.module("zqlite") },
            },
        }),
        .use_lld = llvm,
        .use_llvm = llvm,
    });
    b.installArtifact(exe);

    // run step
    const run = b.step("run", "run the tool");
    run.dependOn(&b.addRunArtifact(exe).step);
}
