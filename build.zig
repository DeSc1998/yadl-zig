const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const program_name = if (target.query.os_tag == .macos) "yadl-mac" else if (target.query.os_tag == .windows) "yadl-win" else "yadl-linux";

    const yadl = b.addStaticLibrary(.{
        .name = "yadl",
        .root_source_file = b.path("lib/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = program_name,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("yadl", &yadl.root_module);

    b.installArtifact(yadl);
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_utils = b.addSharedLibrary(.{
        .name = "test-utils",
        .root_source_file = b.path("src/test_utils.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_utils.root_module.addImport("yadl", &yadl.root_module);

    const test_dirs: []const []const u8 = &[_][]const u8{
        "array",
        "control_flow",
        "data_loading",
        "dictionaries",
        "expressions",
        "failing",
        "functions",
        "iterator",
        "miscellaneous",
        "scoping",
        "stdlib",
        "strings",
        "type_conversions",
    };

    const exe_unit_tests = b.addTest(.{
        .name = "parser",
        .root_source_file = b.path("lib/Parser.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit and script tests");
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    test_step.dependOn(&run_exe_unit_tests.step);

    for (test_dirs) |dir| {
        const path = b.pathJoin(&[_][]const u8{ "test", dir, "test.zig" });
        const test_case = b.addTest(.{
            .name = dir,
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
        });
        test_case.root_module.addImport("test-utils", &test_utils.root_module);
        const run_test_case = b.addRunArtifact(test_case);
        test_step.dependOn(&run_test_case.step);
    }
}
