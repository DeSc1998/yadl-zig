const std = @import("std");

var should_build_release = false;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const program_name = if (target.query.os_tag == .macos) "yadl-mac" else if (target.query.os_tag == .windows) "yadl-win" else "yadl-linux";

    // core binaries
    const yadl_stdlib = b.addLibrary(.{
        .linkage = .static,
        .name = "yadl-stdlib",
        .root_module = b.createModule(.{
            .root_source_file = b.path("lib/stdlib_source.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const yadl = b.addLibrary(.{
        .linkage = .static,
        .name = "yadl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("lib/lib.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "yadl-stdlib", .module = yadl_stdlib.root_module },
            },
        }),
    });

    const exe = b.addExecutable(.{
        .name = program_name,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("yadl", yadl.root_module);

    const parzig = b.dependency("parzig", .{});
    const parzig_mod = parzig.module("parzig");
    const lsp_server = b.addExecutable(.{
        .name = "yls",
        .root_source_file = b.path("src/lsp/server.zig"),
        .target = target,
        .optimize = optimize,
    });
    lsp_server.root_module.addImport("parzig", parzig_mod);

    b.installArtifact(yadl);
    b.installArtifact(exe);
    b.installArtifact(lsp_server);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const run_dump_cmd = b.addRunArtifact(exe);
    const run_dump_step = b.step("run-fulldump", "Run the app with dumped disassembled bytecode");
    run_dump_step.dependOn(&run_dump_cmd.step);
    run_dump_cmd.addArg("-d");
    run_dump_cmd.addArg("--dump-to-file");
    if (b.args) |args| {
        run_dump_cmd.addArgs(args);
    }

    const lsp_cmd = b.addRunArtifact(lsp_server);
    lsp_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        lsp_cmd.addArgs(args);
    }
    const lsp_step = b.step("lsp", "Run the lsp server");
    lsp_step.dependOn(&lsp_cmd.step);

    // testing
    const test_utils = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "test-utils",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_utils.zig"),
            .target = target,
            .optimize = optimize,
        }),
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

    const riscv_unit_tests = b.addTest(.{
        .name = "risc-v",
        .root_source_file = b.path("lib/riscv/instruction.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit and script tests");
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const run_riscv_unit_tests = b.addRunArtifact(riscv_unit_tests);
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_riscv_unit_tests.step);

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

    if (findPytest(b)) |path| {
        const pytest_step = b.step("pytest", "Run pytest with arguments");
        var args = std.ArrayList([]const u8).init(b.allocator);
        args.append(path) catch @panic("OOM");
        if (b.args) |arguments|
            args.appendSlice(arguments) catch @panic("OOM");
        const pytest_command = b.addSystemCommand(args.items);
        pytest_step.dependOn(b.getInstallStep());
        pytest_step.dependOn(&pytest_command.step);
    }
}

fn findPytest(b: *std.Build) ?[]const u8 {
    if (b.findProgram(&.{"pytest"}, &.{})) |path| {
        return path;
    } else |_| return null;
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
    const yadl_release = b.addLibrary(.{
        .linkage = .static,
        .name = lib_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("lib/lib.zig"),
            .target = options_release,
            .optimize = mode,
        }),
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
