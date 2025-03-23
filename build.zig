const std = @import("std");

var should_build_release = false;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const program_name = if (target.query.os_tag == .macos) "yadl-mac" else if (target.query.os_tag == .windows) "yadl-win" else "yadl-linux";

    // core binaries
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
    exe.root_module.addImport("yadl", yadl.root_module);

    const run_cmd = b.addRunArtifact(exe);

    b.installArtifact(yadl);
    b.installArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // testing
    const test_utils = b.addSharedLibrary(.{
        .name = "test-utils",
        .root_source_file = b.path("src/test_utils.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_utils.root_module.addImport("yadl", yadl.root_module);

    const test_dirs: []const []const u8 = &[_][]const u8{
        "array",
        "control_flow",
        "data_loading",
        "dictionaries",
        "expressions",
        "examples",
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
        test_case.root_module.addImport("test-utils", test_utils.root_module);
        const run_test_case = b.addRunArtifact(test_case);
        test_step.dependOn(&run_test_case.step);
    }

    // clean up
    const clean_step = b.step("clean", "Remove output and cache directory");
    const clean_output = b.addRemoveDirTree(b.path("./zig-out/"));
    const clean_cache = b.addRemoveDirTree(b.path("./.zig-cache/"));
    clean_step.dependOn(&clean_output.step);
    clean_step.dependOn(&clean_cache.step);

    // building releases
    const release_step = b.step("release", "Build all release targets");
    if (b.option(bool, "add-release", "adds all release build targets (default: false)")) |_| {
        should_build_release = true;
    }
    addBinary(b, release_step, .linux, .x86_64, .ReleaseFast);
    addBinary(b, release_step, .windows, .x86_64, .ReleaseFast);
    addBinary(b, release_step, .macos, .aarch64, .ReleaseFast);
}

fn addBinary(
    b: *std.Build,
    release_step: *std.Build.Step,
    os: std.Target.Os.Tag,
    arch: std.Target.Cpu.Arch,
    mode: std.builtin.OptimizeMode,
) void {
    const options_release = b.resolveTargetQuery(.{
        .os_tag = os,
        .cpu_arch = arch,
    });
    const lib_name = std.mem.join(b.allocator, "-", &.{ "yadl", "lib", @tagName(os), @tagName(arch) }) catch @panic("OOM");
    const yadl_release = b.addStaticLibrary(.{
        .name = lib_name,
        .root_source_file = b.path("lib/lib.zig"),
        .target = options_release,
        .optimize = mode,
    });

    const exe_name = std.mem.join(b.allocator, "-", &.{ "yadl", @tagName(os), @tagName(arch) }) catch @panic("OOM");
    const yadl_exe = b.addExecutable(.{
        .name = exe_name,
        .root_source_file = b.path("src/main.zig"),
        .target = options_release,
        .optimize = mode,
    });
    yadl_exe.root_module.addImport("yadl", yadl_release.root_module);

    release_step.dependOn(&yadl_release.step);
    release_step.dependOn(&yadl_exe.step);

    if (should_build_release)
        b.installArtifact(yadl_exe);
}
