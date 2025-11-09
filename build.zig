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
    const zmig = b.dependency("zmig", dep_args);
    // hack: use same version of sqlite as zmig
    //       without this, compiler complains about "different" types
    const sqlite = zmig.builder.dependency("sqlite", dep_args);

    // exe
    const exe = b.addExecutable(.{
        .name = "collector",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ptz", .module = ptz.module("ptz") },
                .{ .name = "sqlite", .module = sqlite.module("sqlite") },
                .{ .name = "vaxis", .module = vaxis.module("vaxis") },
                .{ .name = "zmig", .module = zmig.module("zmig") },
            },
        }),
        .use_lld = llvm,
        .use_llvm = llvm,
    });
    b.installArtifact(exe);

    // run step
    const run = b.step("run", "run the tool");
    run.dependOn(&b.addRunArtifact(exe).step);

    // migrations
    const clone = zmig.builder.named_writefiles.get("clone_migrations").?;
    _ = clone.addCopyDirectory(b.path("migrations"), "", .{
        .include_extensions = &.{".sql"},
    });

    const zmig_run = b.addRunArtifact(
        b.addExecutable(.{
            .root_module = zmig.module("zmig-cli"),
            // Enabled due to https://github.com/vrischmann/zig-sqlite/issues/195
            .use_llvm = true,
            .name = "zmig-cli",
        }),
    );
    const zmig_step = b.step("zmig", "Invokes the zmig-cli tool");
    zmig_step.dependOn(&zmig_run.step);
    if (b.args) |args| zmig_run.addArgs(args);
}
