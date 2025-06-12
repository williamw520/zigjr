const std = @import("std");


pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip_debug_symbols = b.option(bool, "strip", "strip debugging symbols") orelse false;

    const zigjr_mod = b.addModule("zigjr", .{
        .root_source_file = b.path("src/zigjr.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip_debug_symbols,
    });

    const cli_exe_mod = b.createModule(.{
        .root_source_file = b.path("src/zigjr-cli.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip_debug_symbols,
    });
    cli_exe_mod.addImport("zigjr", zigjr_mod);

    const cli_exe = b.addExecutable(.{
        .name = "zigjr-cli",
        .root_module = cli_exe_mod,
    });
    b.installArtifact(cli_exe);

    const run_cmd = b.addRunArtifact(cli_exe);


    // Building examples

    const commonOptions = std.Build.Module.CreateOptions {
        .target = target,
        .optimize = optimize,
        .strip = strip_debug_symbols,
    };

    var hello_opt = commonOptions;
    hello_opt.root_source_file = b.path("src/examples/hello.zig");
    const hello_mod = b.createModule(hello_opt);
    hello_mod.addImport("zigjr", zigjr_mod);
    b.installArtifact(b.addExecutable(.{ .name = "hello", .root_module = hello_mod }));

    var hello_stream_opt = commonOptions;
    hello_stream_opt.root_source_file = b.path("src/examples/hello_stream.zig");
    const hello_stream_mod = b.createModule(hello_stream_opt);
    hello_stream_mod.addImport("zigjr", zigjr_mod);
    b.installArtifact(b.addExecutable(.{ .name = "hello_stream", .root_module = hello_stream_mod }));

    var calc_opt = commonOptions;
    calc_opt.root_source_file = b.path("src/examples/calc.zig");
    const calc_mod = b.createModule(calc_opt);
    calc_mod.addImport("zigjr", zigjr_mod);
    b.installArtifact(b.addExecutable(.{ .name = "calc", .root_module = calc_mod }));

    var calc_stream_opt = commonOptions;
    calc_stream_opt.root_source_file = b.path("src/examples/calc_stream.zig");
    const calc_stream_mod = b.createModule(calc_stream_opt);
    calc_stream_mod.addImport("zigjr", zigjr_mod);
    b.installArtifact(b.addExecutable(.{ .name = "calc_stream", .root_module = calc_stream_mod }));

    var dispatcher_hello_opt = commonOptions;
    dispatcher_hello_opt.root_source_file = b.path("src/examples/dispatcher_hello.zig");
    const dispatcher_hello_mod = b.createModule(dispatcher_hello_opt);
    dispatcher_hello_mod.addImport("zigjr", zigjr_mod);
    b.installArtifact(b.addExecutable(.{ .name = "dispatcher_hello", .root_module = dispatcher_hello_mod }));

    var dispatcher_counter_opt = commonOptions;
    dispatcher_counter_opt.root_source_file = b.path("src/examples/dispatcher_counter.zig");
    const dispatcher_counter_mod = b.createModule(dispatcher_counter_opt);
    dispatcher_counter_mod.addImport("zigjr", zigjr_mod);
    b.installArtifact(b.addExecutable(.{ .name = "dispatcher_counter", .root_module = dispatcher_counter_mod }));


    // End of building examples

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = zigjr_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = cli_exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
