// Status log for the tray build. main.zig imports this only from tray-only code,
// so the headless build never pulls it in: no file, no writes, no DLL additions.
// Failures are silent on purpose — a log that cannot be opened must never stop
// the app from tagging.
const std = @import("std");

const FILE_APPEND_DATA: u32 = 0x0004;
const FILE_SHARE_ALL: u32 = 0x7;
const CREATE_ALWAYS: u32 = 2;
const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;
const INVALID_HANDLE: usize = @bitCast(~@as(usize, 0));

extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*anyopaque, u32, u32, ?*anyopaque) callconv(.C) *anyopaque;
extern "kernel32" fn WriteFile(*anyopaque, [*]const u8, u32, *u32, ?*anyopaque) callconv(.C) c_int;
extern "kernel32" fn CloseHandle(?*anyopaque) callconv(.C) c_int;

var handle: ?*anyopaque = null;

// Opens the log at a UTF-16 path, truncating whatever was there. One file per
// run: the log always describes the current session, so it cannot grow forever.
pub fn open(path_utf16: [*:0]const u16) void {
    const h = CreateFileW(path_utf16, FILE_APPEND_DATA, FILE_SHARE_ALL, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
    if (@intFromPtr(h) == INVALID_HANDLE) return;
    handle = h;
}

pub fn write(comptime fmt: []const u8, args: anytype) void {
    const h = handle orelse return;
    var buf: [512]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, fmt ++ "\n", args) catch return;
    var wrote: u32 = 0;
    _ = WriteFile(h, line.ptr, @intCast(line.len), &wrote, null);
}

pub fn close() void {
    if (handle) |h| _ = CloseHandle(h);
    handle = null;
}
