//! The build function in this file should be called from the top level build script

const std = @import("std");

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const lib = b.addSharedLibrary(.{
        .name = "simple",
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();
    lib.linkSystemLibrary("GL");

    lib.addCSourceFile(.{ .file = b.path("examples/simple/simple.c") });
    lib.addIncludePath(b.path("api"));

    b.installArtifact(lib);
}
