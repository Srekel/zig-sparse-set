const std = @import("std");
const builtin = @import("builtin");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});

    const test_all_step = b.step("test", "Run all tests in all modes.");
    inline for ([_]std.builtin.OptimizeMode{ .Debug, .ReleaseFast, .ReleaseSafe, .ReleaseSmall }) |test_mode| {
        const mode_str = @tagName(test_mode);
        const tests = b.addTest(.{
            .root_source_file = .{ .path = "src/test.zig" },
            .target = target,
            .optimize = test_mode,
        });

        tests.setNamePrefix(mode_str ++ " ");
        const test_step = b.step("test-" ++ mode_str, "Run all tests in " ++ mode_str ++ ".");
        test_step.dependOn(&tests.step);
        test_all_step.dependOn(test_step);
    }

    const build_docs = b.addSystemCommand(&[_][]const u8{
        b.zig_exe,
        "test",
        "src/sparse_set.zig",
        "-femit-docs",
        "-fno-emit-bin",
    });

    const all_step = b.step("all", "Build everything and runs all tests");
    all_step.dependOn(&build_docs.step);
    all_step.dependOn(test_all_step);
    b.default_step.dependOn(all_step);
}
