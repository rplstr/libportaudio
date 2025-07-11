# PortAudio for Zig

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This is a Zig package for the [PortAudio](http://www.portaudio.com/) library.
Unnecessary files have been removed, and the build system has been replaced with `build.zig`.

This package is for Zig 0.14.1, with `minimum_zig_version` set to the same value. It will be updated only for STABLE Zig releases.

## Usage

### Adding to your project

1.  Add this repository as a dependency in your `build.zig.zon`.

    ```sh
    zig fetch --save git+https://github.com/rplstr/libportaudio.git

2.  In your `build.zig`, add the dependency and link the `portaudio` artifact.

    ```zig
    // build.zig
    const exe = b.addExecutable(...);

    const portaudio_dep = b.dependency("portaudio", .{
        .target = target,
        .optimize = optimize,
        // options
        // for information on all avaliable options run `zig build -h`
        // .shared = true,
        // ...
    });

    exe.linkLibrary(portaudio_dep.artifact("portaudio"));

    exe.addIncludePath(portaudio_dep.path("include"));
    ```

3.  In your Zig code, you can then `@cImport` the header and use the library.

    ```zig
    const pa = @cImport({
        @cInclude("portaudio.h");
    });

    pub fn main() !void {
        var err = pa.Pa_Initialize();
        if (err != pa.paNoError) {
        }
        defer _ = pa.Pa_Terminate();

        // ...
    }
    ```

## Building

To build the library, tests, or examples directly from this repository, use `zig build`

*   Build the library (static by default):
    ```sh
    zig build
    ```

*   Build and install the examples:
    ```sh
    zig build examples -Dexamples=true
    ```

*   Build and run the tests:
    ```sh
    zig build test -Dtests=true
    ```
