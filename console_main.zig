// Console (headless) build of VRCMetadata: the same tagging engine with no window,
// no tray icon and no user32/shell32/gdi32 imports.
//
//   zig build-exe console_main.zig -O ReleaseSmall --subsystem windows -femit-bin=VRCMetadata.exe
//
// `--subsystem windows` keeps it truly silent: no console window and no
// conhost.exe (which cost ~6 MB of working set). It writes NOTHING — no log file,
// no stderr, no %LOCALAPPDATA% folder. The only thing it writes is the metadata
// inside the photos. Use --quit (exit code 1 = nothing was running) to stop it.
// The tray build keeps a status log; see log.zig.
//
// Stop a running instance with `VRCMetadata.exe --quit`; it shares the tray build's
// single-instance mutex, so only one of the two runs.
pub const console_build = true;

const app = @import("main.zig");

pub fn main() void {
    app.main();
}

// Pulls main.zig's tests into `zig test console_main.zig`, so the suite also runs
// in the headless configuration.
test {
    _ = app;
}
