const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const test_all_step = b.step("test", "Run all tests in all modes.");
    inline for ([_]std.builtin.OptimizeMode{ .Debug, .ReleaseFast, .ReleaseSafe, .ReleaseSmall }) |test_mode| {
        const mode_str = @tagName(test_mode);
        const tests = b.addTest(.{
            .name = mode_str ++ " ",
            .root_source_file = .{ .path = "src/test.zig" },
            .target = target,
            .optimize = test_mode,
        });

        const run_test_step = b.addRunArtifact(tests);
        const test_step = b.step("test-" ++ mode_str, "Run all tests in " ++ mode_str ++ ".");
        test_step.dependOn(&run_test_step.step);
        test_all_step.dependOn(test_step);
    }

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/sparse_set.zig" },
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = tests.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const all_step = b.step("all", "Build everything and runs all tests");
    all_step.dependOn(&install_docs.step);
    all_step.dependOn(test_all_step);
    b.default_step.dependOn(all_step);
}
