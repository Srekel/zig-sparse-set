const std = @import("std");
const builtin = @import("builtin");
const Mode = builtin.Mode;
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    const test_all_step = b.step("test", "Run all tests in all modes.");
    inline for ([_]Mode{ Mode.Debug, Mode.ReleaseFast, Mode.ReleaseSafe, Mode.ReleaseSmall }) |test_mode| {
        const mode_str = @tagName(test_mode);
        const tests = b.addTest("src/test.zig");
        tests.setBuildMode(test_mode);
        tests.setNamePrefix(mode_str ++ " ");
        tests.addPackagePath("sparse_set", "sparse_set.zig");

        const test_step = b.step("test-" ++ mode_str, "Run all tests in " ++ mode_str ++ ".");
        test_step.dependOn(&tests.step);
        test_all_step.dependOn(test_step);
    }

    const all_step = b.step("all", "Build everything and runs all tests");
    all_step.dependOn(test_all_step);
    b.default_step.dependOn(all_step);
}
