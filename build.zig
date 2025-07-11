// NOTE: we can't use TranslateC here, because that's just how PortAudio is designed.
const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared = b.option(bool, "shared", "Build a shared library") orelse false;

    const pa_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "portaudio",
        .version = .{ .major = 19, .minor = 8, .patch = 0 },
        .linkage = if (shared) .dynamic else .static,
        .root_module = pa_module,
    });

    lib.addIncludePath(b.path("include"));
    lib.installHeader(b.path("include/portaudio.h"), "portaudio.h");

    lib.addIncludePath(b.path("src/common"));
    lib.addCSourceFiles(.{
        .files = &.{
            "src/common/pa_allocation.c",
            "src/common/pa_converters.c",
            "src/common/pa_cpuload.c",
            "src/common/pa_debugprint.c",
            "src/common/pa_dither.c",
            "src/common/pa_front.c",
            "src/common/pa_process.c",
            "src/common/pa_ringbuffer.c",
            "src/common/pa_stream.c",
            "src/common/pa_trace.c",
        },
    });

    // Endianness
    switch (target.result.cpu.arch.endian()) {
        .big => pa_module.addCMacro("PA_BIG_ENDIAN", "1"),
        .little => pa_module.addCMacro("PA_LITTLE_ENDIAN", "1"),
    }

    // Debug output
    if (b.option(bool, "debug_output", "Enable debug output") orelse false) {
        pa_module.addCMacro("PA_ENABLE_DEBUG_OUTPUT", "1");
    }

    switch (target.result.os.tag) {
        .windows => {
            lib.addIncludePath(b.path("src/os/win"));
            lib.addCSourceFiles(.{
                .files = &.{
                    "src/os/win/pa_win_coinitialize.c",
                    "src/os/win/pa_win_hostapis.c",
                    "src/os/win/pa_win_util.c",
                    "src/os/win/pa_win_version.c",
                    "src/os/win/pa_win_waveformat.c",
                },
            });
            lib.installHeader(b.path("include/pa_win_waveformat.h"), "pa_win_waveformat.h");

            lib.linkSystemLibrary("winmm");
            pa_module.addCMacro("_CRT_SECURE_NO_WARNINGS", "");

            if (target.result.abi == .msvc) {
                lib.addCSourceFile(.{ .file = b.path("src/os/win/pa_x86_plain_converters.c") });
            } else {
                pa_module.addCMacro("_WIN32_WINNT", "0x0501");
                pa_module.addCMacro("WINVER", "0x0501");
            }

            // ASIO
            const use_asio = b.option(bool, "asio", "Enable ASIO support (requires ASIO SDK)") orelse false;
            if (use_asio) {
                const asio_sdk_path = b.option([]const u8, "asio-sdk-path", "Path to the ASIO SDK") orelse "asiosdk";
                lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ asio_sdk_path, "common" }) });
                lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ asio_sdk_path, "host" }) });
                lib.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ asio_sdk_path, "host", "pc" }) });
                lib.addCSourceFiles(.{
                    .files = &.{
                        "src/hostapi/asio/pa_asio.cpp",
                        "src/hostapi/asio/iasiothiscallresolver.cpp",
                    },
                });
                lib.addCSourceFile(.{ .file = .{ .cwd_relative = b.pathJoin(&.{ asio_sdk_path, "common", "asio.cpp" }) } });
                lib.addCSourceFile(.{ .file = .{ .cwd_relative = b.pathJoin(&.{ asio_sdk_path, "host", "asiodrivers.cpp" }) } });
                lib.addCSourceFile(.{ .file = .{ .cwd_relative = b.pathJoin(&.{ asio_sdk_path, "host", "pc", "asiolist.cpp" }) } });
                lib.linkLibCpp();
                pa_module.addCMacro("PA_USE_ASIO", "1");
                lib.installHeader(b.path("include/pa_asio.h"), "pa_asio.h");
            }

            // DirectSound
            const use_ds = b.option(bool, "dsound", "Enable DirectSound support") orelse true;
            if (use_ds) {
                lib.addIncludePath(b.path("src/hostapi/dsound"));
                lib.addCSourceFiles(.{
                    .files = &.{
                        "src/hostapi/dsound/pa_win_ds.c",
                        "src/hostapi/dsound/pa_win_ds_dynlink.c",
                    },
                });
                lib.linkSystemLibrary("dsound");
                pa_module.addCMacro("PA_USE_DS", "1");
                lib.installHeader(b.path("include/pa_win_ds.h"), "pa_win_ds.h");
                if (target.result.abi != .gnu) {
                    pa_module.addCMacro("PAWIN_USE_DIRECTSOUNDFULLDUPLEXCREATE", "");
                }
            }

            // WMME
            const use_wmme = b.option(bool, "wmme", "Enable WMME support") orelse true;
            if (use_wmme) {
                lib.addCSourceFile(.{ .file = b.path("src/hostapi/wmme/pa_win_wmme.c") });
                lib.linkSystemLibrary("ole32");
                lib.linkSystemLibrary("uuid");
                pa_module.addCMacro("PA_USE_WMME", "1");
                lib.installHeader(b.path("include/pa_win_wmme.h"), "pa_win_wmme.h");
            }

            // WASAPI
            const use_wasapi = b.option(bool, "wasapi", "Enable WASAPI support") orelse true;
            if (use_wasapi) {
                lib.addCSourceFile(.{ .file = b.path("src/hostapi/wasapi/pa_win_wasapi.c") });
                lib.linkSystemLibrary("ole32");
                lib.linkSystemLibrary("uuid");
                pa_module.addCMacro("PA_USE_WASAPI", "1");
                lib.installHeader(b.path("include/pa_win_wasapi.h"), "pa_win_wasapi.h");
            }

            // WDM-KS
            const use_wdmks = b.option(bool, "wdmks", "Enable WDM-KS support") orelse true;
            if (use_wdmks) {
                lib.addCSourceFiles(.{
                    .files = &.{
                        "src/os/win/pa_win_wdmks_utils.c",
                        "src/hostapi/wdmks/pa_win_wdmks.c",
                    },
                });
                lib.linkSystemLibrary("setupapi");
                lib.linkSystemLibrary("ole32");
                lib.linkSystemLibrary("uuid");
                pa_module.addCMacro("PA_USE_WDMKS", "1");
                lib.installHeader(b.path("include/pa_win_wdmks.h"), "pa_win_wdmks.h");
            }

            const use_wdmks_device_info = b.option(bool, "wdmks-device-info", "Use WDM/KS API for device info") orelse true;
            if (use_wdmks_device_info) {
                pa_module.addCMacro("PAWIN_USE_WDMKS_DEVICE_INFO", "");
            }
        },

        .macos => {
            lib.addIncludePath(b.path("src/os/unix"));
            lib.addCSourceFiles(.{
                .files = &.{
                    "src/os/unix/pa_unix_hostapis.c",
                    "src/os/unix/pa_unix_util.c",
                    "src/os/unix/pa_pthread_util.c",
                },
                .flags = &.{"-std=c11"},
            });

            lib.addIncludePath(b.path("src/hostapi/coreaudio"));
            lib.addCSourceFiles(.{
                .files = &.{
                    "src/hostapi/coreaudio/pa_mac_core.c",
                    "src/hostapi/coreaudio/pa_mac_core_blocking.c",
                    "src/hostapi/coreaudio/pa_mac_core_utilities.c",
                },
                .flags = &.{"-std=c11"},
            });

            lib.linkFramework("CoreAudio");
            lib.linkFramework("AudioToolbox");
            lib.linkFramework("AudioUnit");
            lib.linkFramework("CoreFoundation");
            lib.linkFramework("CoreServices");

            pa_module.addCMacro("PA_USE_COREAUDIO", "1");
            lib.installHeader(b.path("include/pa_mac_core.h"), "pa_mac_core.h");
        },

        else => { // Other Unix-like
            lib.addIncludePath(b.path("src/os/unix"));
            lib.addCSourceFiles(.{
                .files = &.{
                    "src/os/unix/pa_unix_hostapis.c",
                    "src/os/unix/pa_unix_util.c",
                    "src/os/unix/pa_pthread_util.c",
                },
            });
            lib.linkSystemLibrary("m");
            lib.linkSystemLibrary("pthread");

            // ALSA
            const use_alsa = b.option(bool, "alsa", "Enable ALSA support") orelse (target.result.os.tag == .linux);
            if (use_alsa) {
                lib.addCSourceFile(.{ .file = b.path("src/hostapi/alsa/pa_linux_alsa.c") });
                pa_module.addCMacro("PA_USE_ALSA", "1");
                lib.installHeader(b.path("include/pa_linux_alsa.h"), "pa_linux_alsa.h");
                const alsa_dynamic = b.option(bool, "alsa-dynamic", "Dynamically load libasound") orelse false;
                if (alsa_dynamic) {
                    pa_module.addCMacro("PA_ALSA_DYNAMIC", "1");
                    lib.linkSystemLibrary("dl");
                } else {
                    lib.linkSystemLibrary("asound");
                }
            }

            // JACK
            const use_jack = b.option(bool, "jack", "Enable JACK support") orelse false;
            if (use_jack) {
                lib.addCSourceFile(.{ .file = b.path("src/hostapi/jack/pa_jack.c") });
                lib.linkSystemLibrary("jack");
                pa_module.addCMacro("PA_USE_JACK", "1");
                lib.installHeader(b.path("include/pa_jack.h"), "pa_jack.h");
            }

            // OSS
            const use_oss = b.option(bool, "oss", "Enable OSS support") orelse false;
            if (use_oss) {
                lib.addCSourceFile(.{ .file = b.path("src/hostapi/oss/pa_unix_oss.c") });
                pa_module.addCMacro("PA_USE_OSS", "1");
            }

            // PulseAudio
            const use_pulse = b.option(bool, "pulseaudio", "Enable PulseAudio support") orelse false;
            if (use_pulse) {
                lib.addCSourceFiles(.{
                    .files = &.{
                        "src/hostapi/pulseaudio/pa_linux_pulseaudio_block.c",
                        "src/hostapi/pulseaudio/pa_linux_pulseaudio.c",
                        "src/hostapi/pulseaudio/pa_linux_pulseaudio_cb.c",
                    },
                });
                lib.linkSystemLibrary("pulse");
                pa_module.addCMacro("PA_USE_PULSEAUDIO", "1");
            }

            // sndio
            const use_sndio = b.option(bool, "sndio", "Enable sndio support") orelse false;
            if (use_sndio) {
                lib.addCSourceFile(.{ .file = b.path("src/hostapi/sndio/pa_sndio.c") });
                lib.linkSystemLibrary("sndio");
                pa_module.addCMacro("PA_USE_SNDIO", "1");
            }
        },
    }

    b.installArtifact(lib);

    // Tests
    const build_tests = b.option(bool, "tests", "Build test programs") orelse false;
    const test_step = b.step("test", "Run all PortAudio tests");
    if (build_tests) {
        addTests(b, test_step, lib, target, optimize);
    }

    // Examples
    const build_examples = b.option(bool, "examples", "Build example programs") orelse false;
    const examples_step = b.step("examples", "Build example programs");
    if (build_examples) {
        addExamples(b, examples_step, lib, target, optimize);
    }
}

fn addTests(b: *std.Build, test_step: *std.Build.Step, lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const tests = [_][]const u8{
        "patest_buffer",       "patest_callbackstop", "patest_clip",             "patest_converters",
        "patest_dither",       "patest_hang",         "patest_in_overflow",      "patest_latency",
        "patest_leftright",    "patest_longsine",     "patest_many",             "patest_maxsines",
        "patest_mono",         "patest_multi_sine",   "patest_out_underflow",    "patest_prime",
        "patest_ringmix",      "patest_sine8",        "patest_sine_channelmaps", "patest_sine_formats",
        "patest_sine_srate",   "patest_sine_time",    "patest_start_stop",       "patest_stop",
        "patest_stop_playout", "patest_toomanysines", "patest_two_rates",        "patest_underflow",
        "patest_wire",         "pa_devs",             "pa_fuzz",                 "pa_minlat",
    };

    inline for (tests) |test_name| {
        const exe_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        });
        const exe = b.addExecutable(.{
            .name = test_name,
            .root_module = exe_module,
        });
        exe.addCSourceFile(.{ .file = b.path(b.fmt("test/{s}.c", .{test_name})) });
        exe.linkLibrary(lib);
        // if posix
        if (target.result.os.tag != .windows and !target.result.os.tag.isDarwin()) {
            exe.linkSystemLibrary("m");
        }
        const run_cmd = b.addRunArtifact(exe);
        test_step.dependOn(&run_cmd.step);
    }
}

fn addExamples(b: *std.Build, examples_step: *std.Build.Step, lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const examples = [_][]const u8{
        "paex_pink", "paex_read_write_wire", "paex_record",            "paex_saw",
        "paex_sine", "paex_write_sine",      "paex_write_sine_nonint",
    };

    inline for (examples) |example_name| {
        const exe_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        });
        const exe = b.addExecutable(.{
            .name = example_name,
            .root_module = exe_module,
        });
        exe.addCSourceFile(.{ .file = b.path(b.fmt("examples/{s}.c", .{example_name})) });
        exe.linkLibrary(lib);
        // if posix
        if (target.result.os.tag != .windows and !target.result.os.tag.isDarwin()) {
            exe.linkSystemLibrary("m");
        }
        const install_exe = b.addInstallArtifact(exe, .{});
        examples_step.dependOn(&install_exe.step);
    }
}
