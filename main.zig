// VRCMetadata (Zig) — tray app tagging new VRChat screenshots with VRCX-compatible
// session metadata. Local sources only: the photo's native XMP + VRChat output logs.
//
// Tray build output IS this folder's VRCMetadata-gui.exe (the plain VRCMetadata.exe
// is the headless build, from console_main.zig), not a copy in Downloads or anywhere
// else. Rebuild in place:
//   zig build-exe main.zig -O ReleaseSmall --subsystem windows -femit-bin=VRCMetadata-gui.exe
const std = @import("std");
// Tray-only status log. Imported from tray code paths exclusively; the headless
// build never references it (see log.zig).
const log = @import("log.zig");

// Identity, in two parts.
// `app` is what the program calls itself: exe/docs name, tray tooltip, log dir,
// status messages, single-instance mutex/event. Renaming the tool = change this
// (plus the two wide-char name arrays below, which cannot be built from it).
// `payload_app` is the FORMAT ID written into every photo's Description chunk. It
// stays "VRCPicTag" for good: existing photos carry it, readers key on it, and it
// is not a product name.
const app = "VRCMetadata";
const payload_app = "VRCPicTag";

// Two builds share this source. `console_main.zig` sets `console_build = true`
// for the headless exe (VRCMetadata.exe): no window, no tray icon, no
// user32/shell32/gdi32 in the import table at all — everything that touches
// them is dead code in that build. The default build (this file as root) is the
// tray app.
const build_root = @import("root");
const headless: bool = if (@hasDecl(build_root, "console_build")) build_root.console_build else false;

// ---------------------------------------------------------------- win32

const FILETIME = extern struct { low: u32, high: u32 };
fn ftU64(ft: FILETIME) u64 {
    return (@as(u64, ft.high) << 32) | ft.low;
}

const SYSTEMTIME = extern struct {
    year: u16,
    month: u16,
    dow: u16,
    day: u16,
    hour: u16,
    minute: u16,
    second: u16,
    ms: u16,
};

const POINT = extern struct { x: i32, y: i32 };
const RECT = extern struct { left: i32, top: i32, right: i32, bottom: i32 };

const WIN32_FIND_DATAW = extern struct {
    attrs: u32,
    ftCreation: FILETIME,
    ftAccess: FILETIME,
    ftWrite: FILETIME,
    size_high: u32,
    size_low: u32,
    reserved0: u32,
    reserved1: u32,
    name: [260]u16,
    alt_name: [14]u16,
};

const Guid = extern struct { a: u32, b: u16, c: u16, d: [8]u8 };

const NOTIFYICONDATAW = extern struct {
    cb_size: u32,
    hwnd: ?*anyopaque,
    uid: u32,
    flags: u32,
    callback_msg: u32,
    hicon: ?*anyopaque,
    sz_tip: [128]u16,
    state: u32,
    state_mask: u32,
    sz_info: [256]u16,
    u_timeout: u32,
    sz_info_title: [64]u16,
    info_flags: u32,
    guid: Guid,
    hicon_balloon: ?*anyopaque,
};

const WNDCLASSW = extern struct {
    style: u32,
    lpfn_wnd_proc: *const fn (?*anyopaque, u32, usize, isize) callconv(.C) isize,
    cb_cls_extra: i32,
    cb_wnd_extra: i32,
    hinstance: ?*anyopaque,
    hicon: ?*anyopaque,
    hcursor: ?*anyopaque,
    hbr_background: ?*anyopaque,
    lpsz_menu_name: ?*const u16,
    lpsz_class_name: [*:0]const u16,
    hicon_sm: ?*anyopaque,
};

const MSG = extern struct {
    hwnd: ?*anyopaque,
    message: u32,
    wparam: usize,
    lparam: isize,
    time: u32,
    pt: POINT,
};

const GENERIC_READ: u32 = 0x80000000;
const GENERIC_WRITE: u32 = 0x40000000;
const FILE_SHARE_ALL: u32 = 0x7;
const OPEN_EXISTING: u32 = 3;
const CREATE_ALWAYS: u32 = 2;
const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;
const FILE_ATTRIBUTE_DIRECTORY: u32 = 0x10;
const MOVEFILE_REPLACE_EXISTING: u32 = 1;
const MOVEFILE_WRITE_THROUGH: u32 = 8;
const WS_POPUP: u32 = 0x80000000;
const CW_USEDEFAULT: i32 = @bitCast(@as(u32, 0x80000000));
const WM_USER: u32 = 0x0400;
const WM_DESTROY: u32 = 0x0002;
const WM_CLOSE: u32 = 0x0010;
const WM_TIMER: u32 = 0x0113;
const WM_RBUTTONUP: u32 = 0x0205;
const WM_CONTEXTMENU: u32 = 0x0337;
const WM_QUERYENDSESSION: u32 = 0x0011;
const WM_ENDSESSION: u32 = 0x0016;
const NIM_ADD: u32 = 0;
const NIM_SETVERSION: u32 = 4;
const NIF_SHOWTIP: u32 = 0x0080;
const NOTIFYICON_VERSION_4: u32 = 4;
const NIM_MODIFY: u32 = 1;
const NIM_DELETE: u32 = 2;
const NIF_MESSAGE: u32 = 1;
const NIF_ICON: u32 = 2;
const NIF_TIP: u32 = 4;
const MF_STRING: u32 = 0;
const TPM_RIGHTBUTTON: u32 = 0x0002;
const TPM_RETURNCMD: u32 = 0x0100;
const IDI_APPLICATION: usize = 0x7f00;
const INVALID_PTR: usize = @bitCast(~@as(usize, 0));
const IDM_QUIT: usize = 1;
const TIMER_TICK: usize = 1;
const EVENT_MODIFY_STATE: u32 = 0x0002;
const WAIT_OBJECT_0: u32 = 0;
const WAIT_FAILED: u32 = 0xFFFF_FFFF;

extern "kernel32" fn GetModuleHandleW(?*const u16) callconv(.C) ?*anyopaque;
extern "kernel32" fn GetLastError() callconv(.C) u32;
extern "kernel32" fn GetEnvironmentVariableW([*:0]const u16, [*]u16, u32) callconv(.C) u32;
extern "kernel32" fn GetSystemTimeAsFileTime(*FILETIME) callconv(.C) void;
extern "kernel32" fn GetLocalTime(*SYSTEMTIME) callconv(.C) void;
extern "kernel32" fn GetCurrentProcessId() callconv(.C) u32;
extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*anyopaque, u32, u32, ?*anyopaque) callconv(.C) *anyopaque;
extern "kernel32" fn ReadFile(*anyopaque, [*]u8, u32, *u32, ?*anyopaque) callconv(.C) c_int;
extern "kernel32" fn WriteFile(*anyopaque, [*]const u8, u32, *u32, ?*anyopaque) callconv(.C) c_int;
extern "kernel32" fn SetFilePointerEx(*anyopaque, i64, ?*i64, u32) callconv(.C) c_int;
extern "kernel32" fn GetFileSizeEx(*anyopaque, *i64) callconv(.C) c_int;
extern "kernel32" fn CloseHandle(?*anyopaque) callconv(.C) c_int;
extern "kernel32" fn MoveFileExW([*:0]const u16, [*:0]const u16, u32) callconv(.C) c_int;
extern "kernel32" fn DeleteFileW([*:0]const u16) callconv(.C) c_int;
extern "kernel32" fn FindFirstFileW([*:0]const u16, *WIN32_FIND_DATAW) callconv(.C) *anyopaque;
extern "kernel32" fn FindNextFileW(*anyopaque, *WIN32_FIND_DATAW) callconv(.C) c_int;
extern "kernel32" fn FindClose(*anyopaque) callconv(.C) c_int;
extern "kernel32" fn CreateMutexW(?*anyopaque, c_int, [*:0]const u16) callconv(.C) ?*anyopaque;
extern "kernel32" fn CreateDirectoryW([*:0]const u16, ?*anyopaque) callconv(.C) c_int;
extern "kernel32" fn CreateEventW(?*anyopaque, c_int, c_int, ?[*:0]const u16) callconv(.C) ?*anyopaque;
extern "kernel32" fn OpenEventW(u32, c_int, [*:0]const u16) callconv(.C) ?*anyopaque;
extern "kernel32" fn SetEvent(*anyopaque) callconv(.C) c_int;
extern "kernel32" fn WaitForSingleObject(*anyopaque, u32) callconv(.C) u32;

extern "user32" fn RegisterClassW(*const WNDCLASSW) callconv(.C) u16;
extern "user32" fn CreateWindowExW(u32, [*:0]const u16, [*:0]const u16, u32, i32, i32, i32, i32, ?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.C) ?*anyopaque;
extern "user32" fn DefWindowProcW(?*anyopaque, u32, usize, isize) callconv(.C) isize;
extern "user32" fn GetMessageW(*MSG, ?*anyopaque, u32, u32) callconv(.C) i32;
extern "user32" fn TranslateMessage(*const MSG) callconv(.C) c_int;
extern "user32" fn DispatchMessageW(*const MSG) callconv(.C) isize;
extern "user32" fn PostQuitMessage(c_int) callconv(.C) void;
extern "user32" fn SetTimer(?*anyopaque, usize, u32, ?*anyopaque) callconv(.C) usize;
extern "user32" fn KillTimer(?*anyopaque, usize) callconv(.C) c_int;
extern "user32" fn LoadIconW(?*anyopaque, ?*const anyopaque) callconv(.C) ?*anyopaque;
extern "user32" fn CreatePopupMenu() callconv(.C) ?*anyopaque;
extern "user32" fn AppendMenuW(?*anyopaque, u32, usize, [*:0]const u16) callconv(.C) c_int;
extern "user32" fn DestroyMenu(?*anyopaque) callconv(.C) c_int;
extern "user32" fn TrackPopupMenu(?*anyopaque, u32, i32, i32, i32, ?*anyopaque, ?*const RECT) callconv(.C) u32;
extern "user32" fn GetCursorPos(*POINT) callconv(.C) c_int;
extern "user32" fn SetForegroundWindow(?*anyopaque) callconv(.C) c_int;
extern "user32" fn GetSystemMetrics(c_int) callconv(.C) c_int;
extern "user32" fn CreateIconIndirect(*const ICONINFO) callconv(.C) ?*anyopaque;

extern "gdi32" fn CreateDIBSection(?*anyopaque, *const BITMAPINFO, u32, *?*anyopaque, ?*anyopaque, u32) callconv(.C) ?*anyopaque;
extern "gdi32" fn CreateBitmap(c_int, c_int, c_int, c_int, ?*const anyopaque) callconv(.C) ?*anyopaque;
extern "gdi32" fn DeleteObject(?*anyopaque) callconv(.C) c_int;

extern "shell32" fn Shell_NotifyIconW(u32, *const NOTIFYICONDATAW) callconv(.C) c_int;

// ---------------------------------------------------------------- helpers

const PATH_U8: usize = 2048;
const PATH_U16: usize = 1024;

fn utf8ToU16(dst: []u16, src: []const u8) usize {
    var i: usize = 0;
    var o: usize = 0;
    while (i < src.len and o + 2 < dst.len) {
        const b = src[i];
        if (b < 0x80) {
            dst[o] = b;
            o += 1;
            i += 1;
            continue;
        }
        const need = std.unicode.utf8ByteSequenceLength(b) catch {
            dst[o] = 0xFFFD;
            o += 1;
            i += 1;
            continue;
        };
        if (i + @as(usize, need) > src.len) break;
        const cp = std.unicode.utf8Decode(src[i .. i + need]) catch {
            dst[o] = 0xFFFD;
            o += 1;
            i += 1;
            continue;
        };
        if (cp < 0x10000) {
            dst[o] = @truncate(cp);
            o += 1;
        } else {
            const c = cp - 0x10000;
            dst[o] = @truncate(0xD800 + (c >> 10));
            dst[o + 1] = @truncate(0xDC00 + (c & 0x3FF));
            o += 2;
        }
        i += need;
    }
    dst[o] = 0;
    return o;
}

// UTF-16 -> UTF-8. Surrogate PAIRS must be joined into one 4-byte sequence:
// encoding each half separately yields CESU-8, which utf8ToU16 reads back as
// U+FFFD, silently corrupting any path holding a non-BMP character.
fn u16ToU8(dst: []u8, src: []const u16) usize {
    var o: usize = 0;
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        const u = src[i];
        if (u == 0) break;
        var cp: u21 = u;
        if (u >= 0xD800 and u < 0xDC00 and i + 1 < src.len and src[i + 1] >= 0xDC00 and src[i + 1] < 0xE000) {
            cp = 0x10000 + ((@as(u21, u) - 0xD800) << 10) + (@as(u21, src[i + 1]) - 0xDC00);
            i += 1;
        }
        if (cp < 0x80) {
            if (o + 1 > dst.len) break;
            dst[o] = @truncate(cp);
            o += 1;
        } else if (cp < 0x800) {
            if (o + 2 > dst.len) break;
            dst[o] = 0xC0 | @as(u8, @truncate(cp >> 6));
            dst[o + 1] = 0x80 | @as(u8, @truncate(cp & 0x3F));
            o += 2;
        } else if (cp < 0x10000) {
            if (o + 3 > dst.len) break;
            dst[o] = 0xE0 | @as(u8, @truncate(cp >> 12));
            dst[o + 1] = 0x80 | @as(u8, @truncate((cp >> 6) & 0x3F));
            dst[o + 2] = 0x80 | @as(u8, @truncate(cp & 0x3F));
            o += 3;
        } else {
            if (o + 4 > dst.len) break;
            dst[o] = 0xF0 | @as(u8, @truncate(cp >> 18));
            dst[o + 1] = 0x80 | @as(u8, @truncate((cp >> 12) & 0x3F));
            dst[o + 2] = 0x80 | @as(u8, @truncate((cp >> 6) & 0x3F));
            dst[o + 3] = 0x80 | @as(u8, @truncate(cp & 0x3F));
            o += 4;
        }
    }
    return o;
}

fn nameLen(fd: *const WIN32_FIND_DATAW) usize {
    for (fd.name, 0..) |c, i| {
        if (c == 0) return i;
    }
    return fd.name.len;
}

const crc_table = blk: {
    @setEvalBranchQuota(100000);
    var t: [256]u32 = undefined;
    var idx: usize = 0;
    while (idx < 256) : (idx += 1) {
        var c: u32 = @intCast(idx);
        for (0..8) |_| c = if (c & 1 != 0) 0xEDB88320 ^ (c >> 1) else c >> 1;
        t[idx] = c;
    }
    break :blk t;
};

fn crc32(data: []const u8) u32 {
    var c: u32 = 0xFFFFFFFF;
    for (data) |b| c = crc_table[(c ^ @as(u32, b)) & 0xFF] ^ (c >> 8);
    return c ^ 0xFFFFFFFF;
}

fn fnv1a(path: []const u8, size: u64) u64 {
    var h: u64 = 0xcbf29ce484222325;
    for (path) |b| {
        h ^= b;
        h *%= 0x100000001b3;
    }
    var s = size;
    while (s != 0) : (s >>= 1) {
        h = (h ^ (s & 1)) *% 0x100000001b3;
    }
    return h;
}

fn daysFromCivil(y_in: i64, m: u8, d: u8) i64 {
    const y = if (m <= 2) y_in - 1 else y_in;
    const era = @divFloor(y, 400);
    const yoe = y - era * 400;
    const mp: i64 = if (m > 2) m - 3 else m + 9;
    const doy = @divFloor(153 * mp + 2, 5) + d - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

fn civilFromDays(day_in: i64) struct { y: i64, m: u8, d: u8 } {
    var z = day_in + 719468;
    const era = @divFloor(z, 146097);
    z -= era * 146097;
    const yoe = @divTrunc(z - @divFloor(z, 1460) + @divFloor(z, 36524) - @divFloor(z, 146096), 365);
    const y = yoe + era * 400;
    const doy = z - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divTrunc(5 * doy + 2, 153);
    const d: u8 = @intCast(doy - @divFloor(153 * mp + 2, 5) + 1);
    const m: u8 = if (mp < 10) @intCast(mp + 3) else @intCast(mp - 9);
    const yr: i64 = if (mp >= 10) y + 1 else y; // mp 10/11 = Jan/Feb; Dec is mp==9, NOT +1
    return .{ .y = yr, .m = m, .d = d };
}

// "2026.11.04 11:14:18" -> epoch seconds
fn parseTs(s: []const u8) ?i64 {
    if (s.len < 19) return null;
    if (s[4] != '.' or s[7] != '.' or s[10] != ' ' or s[13] != ':' or s[16] != ':') return null;
    const y = std.fmt.parseInt(i64, s[0..4], 10) catch return null;
    const mo = std.fmt.parseInt(u8, s[5..7], 10) catch return null;
    const d = std.fmt.parseInt(u8, s[8..10], 10) catch return null;
    const hh = std.fmt.parseInt(u64, s[11..13], 10) catch return null;
    const mi = std.fmt.parseInt(u64, s[14..16], 10) catch return null;
    const se = std.fmt.parseInt(u64, s[17..19], 10) catch return null;
    return daysFromCivil(y, mo, d) * 86400 + @as(i64, @intCast(hh * 3600 + mi * 60 + se));
}

// "2026-11-04T11:14:18.52+00:00" -> epoch seconds
// Verified against real photos: VRChat writes CreateDate as LOCAL wall time with the
// real local offset (e.g. +01:00 in BST). Log-line stamps are the same local wall
// time, and this parser ignores the offset on both sides, so every comparison
// (replay cutoff, filename cutoff) is naive-local vs naive-local: consistent.
// isoNorm relabels with Z, matching what VRCX itself writes.
fn parseCreatedEpoch(raw: []const u8) ?i64 {
    if (raw.len < 19) return null;
    if (raw[4] != '-' or raw[7] != '-' or raw[10] != 'T' or raw[13] != ':' or raw[16] != ':') return null;
    const y = std.fmt.parseInt(i64, raw[0..4], 10) catch return null;
    const mo = std.fmt.parseInt(u8, raw[5..7], 10) catch return null;
    const d = std.fmt.parseInt(u8, raw[8..10], 10) catch return null;
    const hh = std.fmt.parseInt(u64, raw[11..13], 10) catch return null;
    const mi = std.fmt.parseInt(u64, raw[14..16], 10) catch return null;
    const se = std.fmt.parseInt(u64, raw[17..19], 10) catch return null;
    return daysFromCivil(y, mo, d) * 86400 + @as(i64, @intCast(hh * 3600 + mi * 60 + se));
}

// correct ISO normalizer: date+time is raw[0..19]
fn isoNorm(raw: []const u8, dst: *[24]u8) void {
    @memcpy(dst[0..19], raw[0..19]);
    dst[19] = '.';
    var ms = [_]u8{ '0', '0', '0' };
    var i: usize = 19;
    if (i < raw.len and raw[i] == '.') {
        i += 1;
        var j: usize = 0;
        while (j < 3 and i < raw.len and raw[i] >= '0' and raw[i] <= '9') {
            ms[j] = raw[i];
            j += 1;
            i += 1;
        }
    }
    dst[20] = ms[0];
    dst[21] = ms[1];
    dst[22] = ms[2];
    dst[23] = 'Z';
}

fn xmlUnescape(dst: []u8, src: []const u8) usize {
    var o: usize = 0;
    var i: usize = 0;
    while (i < src.len and o < dst.len) {
        if (src[i] == '&') {
            if (std.mem.startsWith(u8, src[i..], "&amp;")) {
                dst[o] = '&';
                o += 1;
                i += 5;
                continue;
            } else if (std.mem.startsWith(u8, src[i..], "&lt;")) {
                dst[o] = '<';
                o += 1;
                i += 4;
                continue;
            } else if (std.mem.startsWith(u8, src[i..], "&gt;")) {
                dst[o] = '>';
                o += 1;
                i += 4;
                continue;
            } else if (std.mem.startsWith(u8, src[i..], "&quot;")) {
                dst[o] = '"';
                o += 1;
                i += 6;
                continue;
            } else if (std.mem.startsWith(u8, src[i..], "&#39;")) {
                dst[o] = '\'';
                o += 1;
                i += 5;
                continue;
            }
        }
        dst[o] = src[i];
        o += 1;
        i += 1;
    }
    return o;
}

// ---------------------------------------------------------------- session

const MAX_PLAYERS = 128;
const ID_CAP = 80;
const NAME_CAP = 256;
const INST_CAP = 512;

const Player = struct {
    id: [ID_CAP]u8 = undefined,
    id_len: u8 = 0,
    name: [NAME_CAP]u8 = undefined,
    name_len: u16 = 0,
};

const Session = struct {
    world_id: [ID_CAP]u8 = undefined,
    world_id_len: u8 = 0,
    instance: [INST_CAP]u8 = undefined,
    instance_len: u16 = 0,
    players: [MAX_PLAYERS]Player = [_]Player{.{}} ** MAX_PLAYERS,
    nplayers: u16 = 0,
    last_world_name: [NAME_CAP]u8 = undefined,
    last_world_name_len: u16 = 0,

    fn findPlayer(self: *Session, id: []const u8) ?usize {
        for (0..self.nplayers) |i| {
            if (std.mem.eql(u8, self.players[i].id[0..self.players[i].id_len], id)) return i;
        }
        return null;
    }

    fn join(self: *Session, name: []const u8, id: []const u8) void {
        if (id.len < 4 or id.len > ID_CAP) return;
        if (self.findPlayer(id)) |pi| {
            const n = @min(name.len, NAME_CAP);
            @memcpy(self.players[pi].name[0..n], name[0..n]);
            self.players[pi].name_len = @intCast(n);
            return;
        }
        if (self.nplayers >= MAX_PLAYERS) return;
        var p = Player{};
        @memcpy(p.id[0..id.len], id);
        p.id_len = @intCast(id.len);
        const n = @min(name.len, NAME_CAP);
        @memcpy(p.name[0..n], name[0..n]);
        p.name_len = @intCast(n);
        self.players[self.nplayers] = p;
        self.nplayers += 1;
    }

    fn leave(self: *Session, id: []const u8) void {
        if (self.findPlayer(id)) |pi| {
            var k = pi;
            while (k + 1 < self.nplayers) : (k += 1) {
                self.players[k] = self.players[k + 1];
            }
            self.nplayers -= 1;
        }
    }

    fn resetWorld(self: *Session, world: []const u8, inst: []const u8) void {
        const wl = @min(world.len, ID_CAP);
        @memcpy(self.world_id[0..wl], world[0..wl]);
        self.world_id_len = @intCast(wl);
        const il = @min(inst.len, INST_CAP);
        @memcpy(self.instance[0..il], inst[0..il]);
        self.instance_len = @intCast(il);
        self.nplayers = 0;
        self.last_world_name_len = 0; // tooltip must not pair an old world name with a new world id
    }
};

var session = Session{};

// ---------------------------------------------------------------- log lines

var camera_path: [PATH_U8]u8 = undefined;
var camera_path_len: usize = 0;

// parse one log line; camera path stashed in camera_path (no side effect beyond session)
fn parseLine(line_in: []const u8) bool { // true = camera line (path stashed)
    var line = line_in;
    while (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];

    if (std.mem.indexOf(u8, line, "Joining wrld_")) |i| {
        const rest = line[i + "Joining ".len ..];
        const colon = std.mem.indexOfScalar(u8, rest, ':') orelse return false;
        const inst_full = std.mem.trimRight(u8, rest[colon + 1 ..], " \t\r");
        session.resetWorld(rest[0..colon], inst_full);
        return false;
    }
    if (std.mem.indexOf(u8, line, "OnPlayerJoined ")) |i| {
        const rest = line[i + "OnPlayerJoined ".len ..];
        const close_idx = std.mem.lastIndexOfScalar(u8, rest, ')') orelse return false;
        const open_idx = std.mem.lastIndexOfScalar(u8, rest[0..close_idx], '(') orelse return false;
        const id = rest[open_idx + 1 .. close_idx];
        if (!std.mem.startsWith(u8, id, "usr_")) return false;
        var un: [NAME_CAP]u8 = undefined;
        const n = xmlUnescape(&un, std.mem.trimRight(u8, rest[0..open_idx], " \t"));
        session.join(un[0..n], id);
        return false;
    }
    if (std.mem.indexOf(u8, line, "OnPlayerLeft ")) |i| {
        const rest = line[i + "OnPlayerLeft ".len ..];
        const close_idx = std.mem.lastIndexOfScalar(u8, rest, ')') orelse return false;
        const open_idx = std.mem.lastIndexOfScalar(u8, rest[0..close_idx], '(') orelse return false;
        const id = rest[open_idx + 1 .. close_idx];
        if (std.mem.startsWith(u8, id, "usr_")) session.leave(id);
        return false;
    }
    if (std.mem.indexOf(u8, line, "[VRC Camera] Took screenshot to: ")) |i| {
        const p = std.mem.trimRight(u8, line[i + "[VRC Camera] Took screenshot to: ".len ..], " ");
        camera_path_len = @min(p.len, PATH_U8);
        @memcpy(camera_path[0..camera_path_len], p[0..camera_path_len]);
        return true;
    }
    return false;
}

// 16 KiB: a VRChat log line is a few hundred bytes. Overlong lines are dropped
// at the same place they always were (feedBytes takes what fits, then resets at
// the newline), so this bounds nothing that used to be whole.
var line_buf: [16384]u8 = undefined;
var line_buf_len: usize = 0;

fn feedOneLine(line: []const u8) bool {
    if (std.mem.indexOf(u8, line, "[Behaviour]") == null and
        std.mem.indexOf(u8, line, "[VRC Camera]") == null) return false;
    return parseLine(line);
}

// Split b into lines. Two modes, one buffer:
//  - stop_at == 0: live tail. on_cam fires for EACH camera line, at its position
//    in the stream, so the roster snapshot matches the moment the shot was taken
//    (several shots in one read would otherwise collapse into a single tag).
//  - stop_at != 0: log replay. Only timestamped [Behaviour] lines matter; returns
//    false as soon as a line passes stop_at (the photo's capture time).
fn feedBytes(b: []const u8, on_cam: ?*const fn () void, stop_at: i64) bool {
    var i: usize = 0;
    while (i < b.len) {
        const nl = std.mem.indexOfScalarPos(u8, b, i, '\n') orelse b.len;
        const piece = b[i..nl];
        if (piece.len > 0 and line_buf_len < line_buf.len) {
            const take = @min(piece.len, line_buf.len - line_buf_len);
            @memcpy(line_buf[line_buf_len .. line_buf_len + take], piece[0..take]);
            line_buf_len += take;
        }
        if (nl < b.len) {
            const line = line_buf[0..line_buf_len];
            line_buf_len = 0;
            if (stop_at != 0) {
                // Stop on ANY timestamped line: a log tail after the photo may be
                // all camera lines, and the roster must not advance past the shot.
                if (line.len >= 19) {
                    if (parseTs(line[0..19])) |ep| {
                        if (ep > stop_at) return false;
                    }
                }
                if (std.mem.indexOf(u8, line, "[Behaviour]") != null) _ = parseLine(line);
            } else if (feedOneLine(line)) {
                if (on_cam) |cb| cb();
            }
        }
        i = nl + 1;
    }
    return true;
}

// ---------------------------------------------------------------- files

var u16_a: [PATH_U16]u16 = undefined;
var u16_b: [PATH_U16]u16 = undefined;

fn openR(path_utf8: []const u8) ?*anyopaque {
    _ = utf8ToU16(&u16_a, path_utf8);
    const h = CreateFileW(@as([*:0]u16, @ptrCast(&u16_a)), GENERIC_READ, FILE_SHARE_ALL, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null);
    if (@intFromPtr(h) == INVALID_PTR) return null;
    return h;
}

// 16 KiB IO window for skip/copy loops; the loops page through it in pieces.
var io_buf: [16384]u8 = undefined;

fn readExact(h: *anyopaque, buf: []u8) bool {
    var off: usize = 0;
    while (off < buf.len) {
        var got: u32 = 0;
        const want: u32 = @intCast(@min(buf.len - off, 65536));
        if (ReadFile(h, @ptrCast(buf.ptr + off), want, &got, null) == 0 or got == 0) return false;
        off += got;
    }
    return true;
}

fn skipBytes(h: *anyopaque, count: u32) bool {
    var left: usize = count;
    while (left > 0) {
        const want = @min(left, io_buf.len);
        if (!readExact(h, io_buf[0..want])) return false;
        left -= want;
    }
    return true;
}

fn writeAll(h: *anyopaque, data: []const u8) bool {
    var off: usize = 0;
    while (off < data.len) {
        var wrote: u32 = 0;
        const want: u32 = @intCast(@min(data.len - off, 65536));
        if (WriteFile(h, @ptrCast(data.ptr + off), want, &wrote, null) == 0 or wrote == 0) return false;
        off += wrote;
    }
    return true;
}

fn copyBytes(from: *anyopaque, to: *anyopaque, count: u32) bool {
    var left: usize = count;
    while (left > 0) {
        const want = @min(left, io_buf.len);
        var got: u32 = 0;
        if (ReadFile(from, &io_buf, @intCast(want), &got, null) == 0 or got == 0) return false;
        if (!writeAll(to, io_buf[0..got])) return false;
        left -= got;
    }
    return true;
}

// ---------------------------------------------------------------- XMP read

const PhotoMeta = struct {
    author_id: [ID_CAP]u8 = undefined,
    author_id_len: u8 = 0,
    author_name: [NAME_CAP]u8 = undefined,
    author_name_len: u16 = 0,
    world_id: [ID_CAP]u8 = undefined,
    world_id_len: u8 = 0,
    world_name: [NAME_CAP]u8 = undefined,
    world_name_len: u16 = 0,
    created: [24]u8 = [_]u8{0} ** 24,
    created_epoch: i64 = 0,
    has_xmp: bool = false,
    has_description: bool = false,
    opened: bool = false, // file opened and PNG signature matched
    saw_iend: bool = false, // chunk walk reached IEND (complete file)
};

// 64 KiB each: only tEXt/iTXt bodies land here (VRChat's XMP is 2-4 KiB; IDAT is
// skipped, never buffered), and inflate_text holds the decompressed copy.
var chunk_text: [65536]u8 = undefined;
var inflate_text: [65536]u8 = undefined;

fn readTagValue(xmp: []const u8, tag: []const u8, dst: []u8) ?[]const u8 {
    const open = std.mem.indexOf(u8, xmp, tag) orelse return null;
    const gt = std.mem.indexOfScalarPos(u8, xmp, open, '>') orelse return null;
    const close = std.mem.indexOfPos(u8, xmp, gt + 1, "</") orelse return null;
    const n = xmlUnescape(dst, xmp[gt + 1 .. close]);
    return dst[0..n];
}

fn extractXmp(payload: []const u8, meta: *PhotoMeta) void {
    if (readTagValue(payload, "<vrc:WorldID>", &meta.world_id)) |v| meta.world_id_len = @intCast(v.len);
    if (readTagValue(payload, "<vrc:WorldDisplayName>", &meta.world_name)) |v| meta.world_name_len = @intCast(v.len);
    if (readTagValue(payload, "<vrc:AuthorID>", &meta.author_id)) |v| meta.author_id_len = @intCast(v.len);
    if (readTagValue(payload, "<xmp:Author>", &meta.author_name)) |v| meta.author_name_len = @intCast(v.len);
    var cbuf: [64]u8 = undefined;
    if (readTagValue(payload, "<xmp:CreateDate>", &cbuf)) |v| {
        if (parseCreatedEpoch(v)) |ep| {
            meta.created_epoch = ep;
            if (v.len >= 19) isoNorm(v, &meta.created);
        }
    }
}

fn readPhotoChunks(path_utf8: []const u8, meta: *PhotoMeta) bool {
    const h = openR(path_utf8) orelse return false;
    defer _ = CloseHandle(h);

    var sig: [8]u8 = undefined;
    if (!readExact(h, &sig)) return false;
    if (!std.mem.eql(u8, &sig, "\x89PNG\r\n\x1a\n")) return false;
    meta.opened = true;

    var header: [8]u8 = undefined;
    while (readExact(h, &header)) {
        const clen = std.mem.readInt(u32, header[0..4], .big);
        const ctype = header[4..8];
        if (clen > chunk_text.len) {
            if (!skipBytes(h, clen)) break;
        } else if (std.mem.eql(u8, ctype, "tEXt")) {
            if (!readExact(h, chunk_text[0..clen])) break;
            const raw = chunk_text[0..clen];
            const nul = std.mem.indexOfScalar(u8, raw, 0) orelse 0;
            if (std.mem.eql(u8, raw[0..nul], "XML:com.adobe.xmp") and nul + 1 <= raw.len) {
                meta.has_xmp = true;
                extractXmp(raw[nul + 1 ..], meta);
            }
        } else if (std.mem.eql(u8, ctype, "iTXt")) {
            if (!readExact(h, chunk_text[0..clen])) break;
            const raw = chunk_text[0..clen];
            const nul = std.mem.indexOfScalar(u8, raw, 0) orelse 0;
            const keyword = raw[0..nul];
            if (std.mem.eql(u8, keyword, "XML:com.adobe.xmp") and nul + 5 <= raw.len) {
                meta.has_xmp = true;
                extractXmp(inflateMaybe(raw, nul), meta);
            } else if (std.mem.eql(u8, keyword, "Description") and nul + 5 <= raw.len) {
                meta.has_description = true;
                const desc = inflateMaybe(raw, nul);
                if (meta.created[0] == 0) {
                    if (std.mem.indexOf(u8, desc, "\"timestamp\":\"")) |ti| {
                        const vs = ti + "\"timestamp\":\"".len; // value starts after the opening quote
                        if (vs + 19 <= desc.len) {
                            const vend = @min(vs + 25, desc.len);
                            if (parseCreatedEpoch(desc[vs..vend])) |ep| {
                                meta.created_epoch = ep;
                                isoNorm(desc[vs..vend], &meta.created);
                            }
                        }
                    }
                }
            }
        } else {
            if (!skipBytes(h, clen)) break;
        }
        var crc: [4]u8 = undefined;
        if (!readExact(h, &crc)) break;
        if (std.mem.eql(u8, ctype, "IEND")) {
            meta.saw_iend = true;
            break;
        }
    }
    return meta.has_xmp;
}

// iTXt payload after keyword NUL: comp flag, method, lang NUL, translated NUL, text
fn inflateMaybe(raw: []const u8, nul: usize) []const u8 {
    const payload: []const u8 = raw[nul + 5 ..];
    if (raw[nul + 1] == 1) {
        var fbs = std.io.fixedBufferStream(raw[nul + 5 ..]);
        var d = std.compress.zlib.decompressor(fbs.reader());
        var n_inf: usize = 0;
        while (n_inf < inflate_text.len) {
            const got = d.read(inflate_text[n_inf..]) catch break;
            if (got == 0) break;
            n_inf += got;
        }
        return inflate_text[0..n_inf];
    }
    return payload;
}

// ---------------------------------------------------------------- iTXt write

// Holds the Description chunk we write: 12 B header + 12 B body header + json,
// so it must exceed json_buf by 24 bytes.
var new_chunk: [32768]u8 = undefined;

fn writeDescriptionChunk(path_utf8: []const u8, json: []const u8) bool {
    var tmp8: [PATH_U8]u8 = undefined;
    // Per-process temp name: the tray's auto-tag and a manual --tag can target
    // the same photo, and a shared name let one writer's MoveFileExW replace
    // the photo with interleaved content. No .png suffix: scan must never pick
    // up leftovers.
    const t = std.fmt.bufPrint(&tmp8, "{s}.vrctag-{d}.tmp", .{ path_utf8, GetCurrentProcessId() }) catch return false;
    _ = utf8ToU16(&u16_a, path_utf8);
    const src_slice: [*:0]u16 = @ptrCast(&u16_a);
    _ = utf8ToU16(&u16_b, t);

    const hs = openR(path_utf8) orelse return false;
    const hd = CreateFileW(@as([*:0]u16, @ptrCast(&u16_b)), GENERIC_WRITE, FILE_SHARE_ALL, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
    if (@intFromPtr(hd) == INVALID_PTR) {
        _ = CloseHandle(hs);
        return false;
    }

    const kw_len: usize = "Description".len;
    const body_len = kw_len + 1 + 4 + json.len;
    var cw: usize = 0;
    if (body_len + 12 <= new_chunk.len) {
        std.mem.writeInt(u32, new_chunk[cw..][0..4], @intCast(body_len), .big);
        cw += 4;
        @memcpy(new_chunk[cw .. cw + 4], "iTXt");
        cw += 4;
        @memcpy(new_chunk[cw .. cw + kw_len], "Description");
        cw += kw_len;
        new_chunk[cw] = 0;
        new_chunk[cw + 1] = 0; // compression flag (stored)
        new_chunk[cw + 2] = 0; // method
        new_chunk[cw + 3] = 0; // language NUL
        new_chunk[cw + 4] = 0; // translated keyword NUL
        cw += 5;
        @memcpy(new_chunk[cw .. cw + json.len], json);
        cw += json.len;
        const c = crc32(new_chunk[4..cw]);
        std.mem.writeInt(u32, new_chunk[cw..][0..4], c, .big);
        cw += 4;
    } else {
        _ = CloseHandle(hs);
        _ = CloseHandle(hd);
        _ = DeleteFileW(@as([*:0]u16, @ptrCast(&u16_b)));
        return false;
    }

    var ok = false;
    var inserted = false;
    var saw_iend = false;
    var hdr: [8]u8 = undefined;
    var header: [8]u8 = undefined;
    if (readExact(hs, &hdr) and writeAll(hd, &hdr)) {
        ok = true;
        chunk_loop: while (readExact(hs, &header)) {
            const clen = std.mem.readInt(u32, header[0..4], .big);
            const ctype = header[4..8];
            if (std.mem.eql(u8, ctype, "iTXt")) {
                if (clen > chunk_text.len) break :chunk_loop;
                if (!readExact(hs, chunk_text[0..clen])) break :chunk_loop;
                var crc: [4]u8 = undefined;
                if (!readExact(hs, &crc)) break :chunk_loop;
                const nul = std.mem.indexOfScalar(u8, chunk_text[0..clen], 0) orelse 0;
                if (std.mem.eql(u8, chunk_text[0..nul], "Description")) continue :chunk_loop; // drop old
                if (!writeAll(hd, &header)) break :chunk_loop;
                if (!writeAll(hd, chunk_text[0..clen])) break :chunk_loop;
                if (!writeAll(hd, &crc)) break :chunk_loop;
            } else {
                if (!writeAll(hd, &header)) break :chunk_loop;
                if (!copyBytes(hs, hd, clen)) break :chunk_loop;
                var crc: [4]u8 = undefined;
                if (!readExact(hs, &crc)) break :chunk_loop;
                if (!writeAll(hd, &crc)) break :chunk_loop;
            }
            if (!inserted and std.mem.eql(u8, ctype, "IHDR")) {
                if (!writeAll(hd, new_chunk[0..cw])) break :chunk_loop;
                inserted = true;
            }
            if (std.mem.eql(u8, ctype, "IEND")) {
                saw_iend = true;
                break :chunk_loop;
            }
        }
    }
    _ = CloseHandle(hs);
    _ = CloseHandle(hd);

    if (ok and inserted and saw_iend) {
        if (MoveFileExW(@ptrCast(&u16_b), src_slice, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0) return true;
    }
    _ = DeleteFileW(@as([*:0]u16, @ptrCast(&u16_b)));
    return false;
}

// ---------------------------------------------------------------- JSON

// 24 KiB: a full 80-player instance with long names is ~10 KiB. Overflow is a
// clean skip (buildJson returns "", tagPhoto returns .skipped), never a partial write.
var json_buf: [24576]u8 = undefined;

fn jsonEscape(w: anytype, s: []const u8) void {
    for (s) |ch| {
        switch (ch) {
            '"' => w.writeAll("\\\"") catch {},
            '\\' => w.writeAll("\\\\") catch {},
            '\n' => w.writeAll("\\n") catch {},
            '\r' => w.writeAll("\\r") catch {},
            '\t' => w.writeAll("\\t") catch {},
            else => {
                if (ch < 0x20) {
                    w.print("\\u{x:0>4}", .{ch}) catch {};
                } else {
                    w.writeByte(ch) catch {};
                }
            },
        }
    }
}

fn writePlayerJson(w: anytype, p: Player) void {
    w.writeAll("{\"id\":\"") catch return;
    jsonEscape(w, p.id[0..p.id_len]);
    w.writeAll("\",\"displayName\":\"") catch return;
    jsonEscape(w, p.name[0..p.name_len]);
    w.writeAll("\"}") catch return;
}

fn buildJson(meta: *const PhotoMeta, inst: []const u8, pl: []const Player, extra: ?Player, ts: []const u8) []const u8 {
    var fbs = std.io.fixedBufferStream(&json_buf);
    const w = fbs.writer();
    w.writeAll("{\"application\":\"") catch return "";
    w.writeAll(payload_app) catch return ""; // frozen format id, NOT the product name
    w.writeAll("\",\"version\":1,\"author\":{\"id\":\"") catch return "";
    jsonEscape(w, meta.author_id[0..meta.author_id_len]);
    w.writeAll("\",\"displayName\":\"") catch return "";
    jsonEscape(w, meta.author_name[0..meta.author_name_len]);
    w.writeAll("\"},\"world\":{\"id\":\"") catch return "";
    jsonEscape(w, meta.world_id[0..meta.world_id_len]);
    w.writeAll("\",\"name\":\"") catch return "";
    jsonEscape(w, meta.world_name[0..meta.world_name_len]);
    w.writeAll("\",\"instanceId\":\"") catch return "";
    jsonEscape(w, inst);
    w.writeAll("\"},\"players\":[") catch return "";
    for (pl, 0..) |p, i| {
        if (i != 0) w.writeByte(',') catch return "";
        writePlayerJson(w, p);
    }
    if (extra) |p| {
        if (pl.len != 0) w.writeByte(',') catch return "";
        writePlayerJson(w, p);
    }
    w.writeAll("],\"timestamp\":\"") catch return "";
    jsonEscape(w, ts);
    w.writeAll("\"}") catch return "";
    return fbs.getWritten();
}

const TagResult = enum { tagged, skipped, failed };

fn tagPhoto(path_utf8: []const u8, pl_in: []const Player, allow_retag: bool) TagResult {
    var meta = PhotoMeta{};
    if (!readPhotoChunks(path_utf8, &meta)) {
        if (!meta.opened) return .failed; // could not open: file locked?
        if (!meta.saw_iend) return .failed; // still being written; retry later
        return .skipped; // complete file without usable XMP
    }
    if (meta.world_id_len == 0) return .skipped;
    if (meta.has_description and !allow_retag) return .skipped;
    if (meta.created[0] == 0) {
        meta.created_epoch = localNowEpoch();
        epochToIso(meta.created_epoch, &meta.created); // no CreateDate in XMP: photo time = now
    }

    // Live session world must match the photo's XMP world. World switch or a
    // log gap means session.instance/roster belong to a DIFFERENT world: trust
    // only the photo then (empty instanceId, author-only player list).
    const world_ok = std.mem.eql(u8, session.world_id[0..session.world_id_len], meta.world_id[0..meta.world_id_len]);
    const pl: []const Player = if (world_ok) pl_in else &[_]Player{};
    const inst: []const u8 = if (world_ok) session.instance[0..session.instance_len] else "";

    // VRCX lists the author in players too; add them if the roster lacks them.
    var extra: ?Player = null;
    if (meta.author_id_len > 0) {
        var in_roster = false;
        for (pl) |p| {
            if (std.mem.eql(u8, p.id[0..p.id_len], meta.author_id[0..meta.author_id_len])) {
                in_roster = true;
                break;
            }
        }
        if (!in_roster) {
            var p = Player{};
            @memcpy(p.id[0..meta.author_id_len], meta.author_id[0..meta.author_id_len]);
            p.id_len = meta.author_id_len;
            const cn: usize = @min(meta.author_name_len, NAME_CAP);
            @memcpy(p.name[0..cn], meta.author_name[0..cn]);
            p.name_len = @intCast(cn);
            extra = p;
        }
    }

    const json = buildJson(&meta, inst, pl, extra, meta.created[0..24]);
    if (json.len == 0) return .skipped; // roster too big for json_buf (unreachable at 64 KB)
    if (!writeDescriptionChunk(path_utf8, json)) return .failed;
    if (meta.world_name_len > 0) {
        @memcpy(session.last_world_name[0..meta.world_name_len], meta.world_name[0..meta.world_name_len]);
        session.last_world_name_len = meta.world_name_len;
    }
    return .tagged;
}

// ---------------------------------------------------------------- processed set

const PROC_SLOTS = 512;
const SENTINEL_SIZE: u64 = 0xFFFF_FFFF_FFFF_FFFE; // size-agnostic claim (camera path)
var proc_hash = [_]u64{0} ** PROC_SLOTS;
var proc_next: usize = 0;

fn isProcessed(path_utf8: []const u8, size: u64) bool {
    const h = fnv1a(path_utf8, size);
    for (proc_hash) |ph| {
        if (ph == h) return true;
    }
    return false;
}

fn markProcessed(path_utf8: []const u8, size: u64) void {
    const h = fnv1a(path_utf8, size);
    for (proc_hash) |ph| {
        if (ph == h) return;
    }
    proc_hash[proc_next] = h;
    proc_next = (proc_next + 1) % PROC_SLOTS;
}

fn unmarkProcessed(path_utf8: []const u8, size: u64) void {
    const h = fnv1a(path_utf8, size);
    for (&proc_hash) |*ph| {
        if (ph.* == h) ph.* = 0;
    }
}

// ---------------------------------------------------------------- dirs

var log_dir: [PATH_U8]u8 = undefined;
var log_dir_len: usize = 0;
var photo_dir: [PATH_U8]u8 = undefined;
var photo_dir_len: usize = 0;
var start_filetime: u64 = 0;

fn getEnvUtf8(name: [*:0]const u16, out: []u8) usize {
    var wb: [PATH_U16]u16 = undefined;
    const r = GetEnvironmentVariableW(name, &wb, PATH_U16);
    if (r == 0 or r >= PATH_U16) return 0;
    return u16ToU8(out, wb[0..r]);
}

fn resolveDirs() bool {
    const n_log = getEnvUtf8(&[_:0]u16{ 'V', 'R', 'C', 'P', 'I', 'C', '_', 'L', 'O', 'G', 'D', 'I', 'R' }, &log_dir);
    if (n_log > 0) {
        log_dir_len = n_log;
    } else {
        var up8: [PATH_U8]u8 = undefined;
        const n = getEnvUtf8(&[_:0]u16{ 'U', 'S', 'E', 'R', 'P', 'R', 'O', 'F', 'I', 'L', 'E' }, &up8);
        if (n == 0) return false;
        const s = std.fmt.bufPrint(&log_dir, "{s}\\AppData\\LocalLow\\VRChat\\VRChat", .{up8[0..n]}) catch return false;
        log_dir_len = s.len;
    }
    const n_ph = getEnvUtf8(&[_:0]u16{ 'V', 'R', 'C', 'P', 'I', 'C', '_', 'P', 'H', 'O', 'T', 'O', 'D', 'I', 'R' }, &photo_dir);
    if (n_ph > 0) {
        photo_dir_len = n_ph;
    } else {
        var up8: [PATH_U8]u8 = undefined;
        const n = getEnvUtf8(&[_:0]u16{ 'U', 'S', 'E', 'R', 'P', 'R', 'O', 'F', 'I', 'L', 'E' }, &up8);
        if (n == 0) return false;
        const s = std.fmt.bufPrint(&photo_dir, "{s}\\Pictures\\VRChat", .{up8[0..n]}) catch return false;
        photo_dir_len = s.len;
    }
    return true;
}

// ---------------------------------------------------------------- log tailing

var live_name: [64]u8 = [_]u8{0} ** 64;
var live_name_len: usize = 0;
var live_off: i64 = 0;
var rbuf: [16384]u8 = undefined; // log read window
var quiet_ticks: u8 = 0;

// Called from feedBytes for every [VRC Camera] line, session state as of that line.
fn onCameraLine() void {
    if (camera_path_len == 0) return;
    const path = camera_path[0..camera_path_len];
    if (isProcessed(path, SENTINEL_SIZE)) return;
    markProcessed(path, SENTINEL_SIZE);
    switch (tagPhoto(path, session.players[0..session.nplayers], false)) {
        .tagged => reportTagged(),
        .skipped => {}, // already tagged or not a VRChat photo: keep the claim
        .failed => unmarkProcessed(path, SENTINEL_SIZE), // e.g. file still locked: let the scan retry
    }
}

// Tail read from live_off to EOF on an already-open handle.
fn tailRead(h: *anyopaque, fsz: i64) void {
    if (fsz < live_off) { // truncated
        live_off = 0;
        line_buf_len = 0;
    }
    var off = live_off;
    while (off < fsz) {
        const want: u32 = @intCast(@min(@as(i64, rbuf.len), fsz - off));
        if (SetFilePointerEx(h, off, null, 0) == 0) break;
        var got: u32 = 0;
        if (ReadFile(h, &rbuf, want, &got, null) == 0 or got == 0) break;
        _ = feedBytes(rbuf[0..got], &onCameraLine, 0);
        off += got; // camera line: partial reads before it already consumed; rest re-scanned next tick
        live_off = off;
    }
}

fn openLive(name: []const u8) ?*anyopaque {
    var full: [PATH_U8]u8 = undefined;
    const fp = std.fmt.bufPrint(&full, "{s}\\{s}", .{ log_dir[0..log_dir_len], name }) catch return null;
    return openR(fp);
}

fn tailTick() void {
    // Fast path: the file we already follow grew. Enumerating the whole log dir
    // was this app's only recurring cost, and VRChat never prunes logs, so that
    // dir grows without bound (measured 26 ms per scan at 3000 files, cold; a
    // 1 Hz scan cost 0.42% of a core). A file that stops growing is the only
    // rotation signal, so the slow path still runs on quiet ticks — once every
    // 30 s: a rotated log is re-read from offset 0, so the delay costs no tags.
    if (live_name_len != 0) {
        if (openLive(live_name[0..live_name_len])) |h| {
            defer _ = CloseHandle(h);
            var fsz: i64 = 0;
            if (GetFileSizeEx(h, &fsz) != 0 and fsz != live_off) {
                quiet_ticks = 0;
                tailRead(h, fsz);
                return;
            }
            quiet_ticks +%= 1;
            if (quiet_ticks < 30) return;
            quiet_ticks = 0;
        }
    }

    var pat: [PATH_U8]u8 = undefined;
    const sp = std.fmt.bufPrint(&pat, "{s}\\output_log_*.txt", .{log_dir[0..log_dir_len]}) catch return;
    _ = utf8ToU16(&u16_a, sp);
    var fd = std.mem.zeroes(WIN32_FIND_DATAW);
    const hfind = FindFirstFileW(@as([*:0]u16, @ptrCast(&u16_a)), &fd);
    if (@intFromPtr(hfind) == INVALID_PTR) return;
    defer _ = FindClose(hfind);

    var best: [64]u8 = undefined;
    var best_len: usize = 0;
    var name8: [300]u8 = undefined;
    var first = true;
    while (true) {
        if (!first) {
            if (FindNextFileW(hfind, &fd) == 0) break;
        }
        first = false;
        if (fd.attrs & FILE_ATTRIBUTE_DIRECTORY != 0) continue;
        const nl = nameLen(&fd);
        if (nl == 0 or nl > 63) continue;
        const l = u16ToU8(&name8, fd.name[0..nl]);
        if (l > best.len) continue; // non-ASCII name can exceed the UTF-8 byte budget
        if (!std.mem.startsWith(u8, name8[0..l], "output_log_")) continue;
        if (best_len == 0 or std.mem.lessThan(u8, best[0..best_len], name8[0..l])) {
            @memcpy(best[0..l], name8[0..l]);
            best_len = l;
        }
    }
    if (best_len == 0) return;

    const switched = best_len != live_name_len or !std.mem.eql(u8, live_name[0..live_name_len], best[0..best_len]);
    if (switched) {
        const rotation = live_name_len != 0; // first attach = seed pass (no camera tags)
        @memcpy(live_name[0..best_len], best[0..best_len]);
        live_name_len = best_len;
        live_off = 0;
        line_buf_len = 0;
        if (!rotation) {
            var full: [PATH_U8]u8 = undefined;
            const fp = std.fmt.bufPrint(&full, "{s}\\{s}", .{ log_dir[0..log_dir_len], best[0..best_len] }) catch return;
            const h = openR(fp) orelse return;
            defer _ = CloseHandle(h);
            var fsz: i64 = 0;
            if (GetFileSizeEx(h, &fsz) == 0) fsz = 0;
            var off: i64 = 0;
            while (off < fsz) {
                const want: u32 = @intCast(@min(@as(i64, rbuf.len), fsz - off));
                if (SetFilePointerEx(h, off, null, 0) == 0) break;
                var got: u32 = 0;
                if (ReadFile(h, &rbuf, want, &got, null) == 0 or got == 0) break;
                _ = feedBytes(rbuf[0..got], null, 0);
                off += got;
            }
            live_off = fsz;
            line_buf_len = 0;
        }
    }

    const h = openLive(live_name[0..live_name_len]) orelse return;
    defer _ = CloseHandle(h);
    var fsz: i64 = 0;
    if (GetFileSizeEx(h, &fsz) == 0) return;
    tailRead(h, fsz);
}

// ---------------------------------------------------------------- fallback scan

var scan_counter: u32 = 0;

fn scanPhotos() void {
    scanDirPhotos("."); // VRChat saves screenshots directly in the photo dir
    var pat: [PATH_U8]u8 = undefined;
    const sp = std.fmt.bufPrint(&pat, "{s}\\*", .{photo_dir[0..photo_dir_len]}) catch return;
    _ = utf8ToU16(&u16_a, sp);
    var fd = std.mem.zeroes(WIN32_FIND_DATAW);
    const hf = FindFirstFileW(@as([*:0]u16, @ptrCast(&u16_a)), &fd);
    if (@intFromPtr(hf) == INVALID_PTR) return;
    defer _ = FindClose(hf);
    var dname: [300]u8 = undefined;
    var first = true;
    while (true) {
        if (!first) {
            if (FindNextFileW(hf, &fd) == 0) break;
        }
        first = false;
        if (fd.attrs & FILE_ATTRIBUTE_DIRECTORY == 0) continue;
        const nl = nameLen(&fd);
        if (nl == 0 or nl > 200) continue;
        const l = u16ToU8(&dname, fd.name[0..nl]);
        if (std.mem.eql(u8, dname[0..l], ".") or std.mem.eql(u8, dname[0..l], "..")) continue;
        scanDirPhotos(dname[0..l]);
    }
}

fn scanDirPhotos(sub: []const u8) void {
    var pat: [PATH_U8]u8 = undefined;
    // sub == "." means the photo dir itself: build the path without the dot so
    // claim keys match the exact paths from camera log lines.
    const sp = if (std.mem.eql(u8, sub, "."))
        std.fmt.bufPrint(&pat, "{s}\\*.png", .{photo_dir[0..photo_dir_len]}) catch return
    else
        std.fmt.bufPrint(&pat, "{s}\\{s}\\*.png", .{ photo_dir[0..photo_dir_len], sub }) catch return;
    _ = utf8ToU16(&u16_a, sp);
    var fd = std.mem.zeroes(WIN32_FIND_DATAW);
    const hf = FindFirstFileW(@as([*:0]u16, @ptrCast(&u16_a)), &fd);
    if (@intFromPtr(hf) == INVALID_PTR) return;
    defer _ = FindClose(hf);
    var fname: [300]u8 = undefined;
    var first = true;
    while (true) {
        if (!first) {
            if (FindNextFileW(hf, &fd) == 0) break;
        }
        first = false;
        if (fd.attrs & FILE_ATTRIBUTE_DIRECTORY != 0) continue;
        if (ftU64(fd.ftWrite) < start_filetime) continue;
        const l = u16ToU8(&fname, fd.name[0..nameLen(&fd)]);
        if (l < 4 or !std.mem.endsWith(u8, fname[0..l], ".png")) continue;
        var full: [PATH_U8]u8 = undefined;
        const fp = if (std.mem.eql(u8, sub, "."))
            std.fmt.bufPrint(&full, "{s}\\{s}", .{ photo_dir[0..photo_dir_len], fname[0..l] }) catch continue
        else
            std.fmt.bufPrint(&full, "{s}\\{s}\\{s}", .{ photo_dir[0..photo_dir_len], sub, fname[0..l] }) catch continue;
        const size: u64 = (@as(u64, fd.size_high) << 32) | fd.size_low;
        if (isProcessed(fp, size) or isProcessed(fp, SENTINEL_SIZE)) continue;
        markProcessed(fp, size); // claim before tagging
        switch (tagPhoto(fp, session.players[0..session.nplayers], false)) {
            .tagged => {
                markProcessed(fp, SENTINEL_SIZE); // write changed the size; sentinel claim is size-agnostic
                reportTagged();
            },
            .skipped => {},
            .failed => unmarkProcessed(fp, size), // locked/mid-write: retry next scan
        }
    }
}

// ---------------------------------------------------------------- tooltip

var tip_u16: [128]u16 = [_]u16{0} ** 128;
var tip_len: usize = 0;
var hwnd_ref: ?*anyopaque = null;
var tray_icon: ?*anyopaque = null;

const BITMAPINFOHEADER = extern struct {
    size: u32,
    width: c_int,
    height: c_int,
    planes: u16,
    bit_count: u16,
    compression: u32,
    size_image: u32,
    x_pels: c_int,
    y_pels: c_int,
    clr_used: u32,
    clr_important: u32,
};
const BITMAPINFO = extern struct {
    header: BITMAPINFOHEADER,
    colors: [1]u32,
};
const ICONINFO = extern struct {
    f_icon: c_int,
    x_hotspot: c_int,
    y_hotspot: c_int,
    hbm_mask: ?*anyopaque,
    hbm_color: ?*anyopaque,
};

// Raw bottom-up 32bpp BGRA bitmaps (generated by tools/make_icons.py).
const ICON32 = @embedFile("icon32.bin");
const ICON16 = @embedFile("icon16.bin");

fn makeIconFromBin(size: c_int, px: []const u8) ?*anyopaque {
    var bmi = std.mem.zeroes(BITMAPINFO);
    bmi.header = .{
        .size = @sizeOf(BITMAPINFOHEADER),
        .width = size,
        .height = size, // bottom-up; the .bin rows are stored bottom-up
        .planes = 1,
        .bit_count = 32,
        .compression = 0,
        .size_image = 0,
        .x_pels = 0,
        .y_pels = 0,
        .clr_used = 0,
        .clr_important = 0,
    };
    var bits: ?*anyopaque = null;
    const dib = CreateDIBSection(null, &bmi, 0, &bits, null, 0) orelse return null;
    if (bits == null) {
        _ = DeleteObject(dib);
        return null;
    }
    const dst: [*]u8 = @ptrCast(bits.?);
    @memcpy(dst[0..px.len], px);
    // All-transparent AND mask: alpha channel drives transparency.
    var mask: [128]u8 = undefined; // (32*32)/8, largest mask we use
    @memset(&mask, 0);
    const hbm_mask = CreateBitmap(size, size, 1, 1, &mask) orelse {
        _ = DeleteObject(dib);
        return null;
    };
    const ii = ICONINFO{
        .f_icon = 1,
        .x_hotspot = 0,
        .y_hotspot = 0,
        .hbm_mask = hbm_mask,
        .hbm_color = dib, // HBITMAP handle, NOT the pixel pointer
    };
    const icon = CreateIconIndirect(&ii);
    // CreateIconIndirect copies both bitmaps; they stay ours to free.
    _ = DeleteObject(hbm_mask);
    _ = DeleteObject(dib);
    return icon;
}

// Tag reporting: the tray shows it in the tooltip and records it in the status
// log; the headless build does neither. `headless` is comptime-known, so the tray
// branch is the only one analysed in the tray exe — and that is what keeps
// user32 out of the headless exe's import table.
fn reportTagged() void {
    if (!headless) {
        updateTooltip();
        const shown: []const u8 = if (session.last_world_name_len > 0)
            session.last_world_name[0..session.last_world_name_len]
        else
            session.world_id[0..session.world_id_len];
        log.write("tagged {s} ({d} player(s))", .{ shown, session.nplayers });
    }
}

// %LOCALAPPDATA%\<app>\status.log, one file per run. Tray-only: paths are built
// here because this file already owns the UTF-8/UTF-16 plumbing.
fn openStatusLog() void {
    var base: [PATH_U8]u8 = undefined;
    const n = getEnvUtf8(&[_:0]u16{ 'L', 'O', 'C', 'A', 'L', 'A', 'P', 'P', 'D', 'A', 'T', 'A' }, &base);
    if (n == 0) return;
    var dir: [PATH_U8]u8 = undefined;
    const d = std.fmt.bufPrint(&dir, "{s}\\{s}", .{ base[0..n], app }) catch return;
    _ = utf8ToU16(&u16_a, d);
    _ = CreateDirectoryW(@ptrCast(&u16_a), null); // already exists is the common case
    var full: [PATH_U8]u8 = undefined;
    const p = std.fmt.bufPrint(&full, "{s}\\status.log", .{d}) catch return;
    _ = utf8ToU16(&u16_b, p);
    log.open(@ptrCast(&u16_b));
}

fn updateTooltip() void {
    if (hwnd_ref == null) return;
    var msg: [1024]u8 = undefined;
    var ml: usize = 0;
    const shown: []const u8 = if (session.world_id_len == 0)
        app
    else if (session.last_world_name_len > 0)
        session.last_world_name[0..session.last_world_name_len]
    else
        session.world_id[0..session.world_id_len];
    if (ml + shown.len <= msg.len) {
        @memcpy(msg[ml .. ml + shown.len], shown);
        ml += shown.len;
    }
    if (session.nplayers > 0 and ml < 100) {
        const sep = " - ";
        @memcpy(msg[ml .. ml + sep.len], sep);
        ml += sep.len;
        var listed: usize = 0;
        for (session.players[0..session.nplayers], 0..) |p, i| {
            if (i >= 8) break;
            const name = p.name[0..p.name_len];
            if (ml + name.len + 3 > 120) break;
            if (listed > 0) {
                msg[ml] = ',';
                ml += 1;
                msg[ml] = ' ';
                ml += 1;
            }
            @memcpy(msg[ml .. ml + name.len], name);
            ml += name.len;
            listed += 1;
        }
        if (session.nplayers > listed) {
            if (std.fmt.bufPrint(msg[ml..], " +{d} more", .{session.nplayers - listed})) |more| {
                ml += more.len;
            } else |_| {}
        }
    }
    var new_tip: [128]u16 = undefined;
    const nl = utf8ToU16(&new_tip, msg[0..ml]);
    if (nl == tip_len and std.mem.eql(u16, new_tip[0..nl], tip_u16[0..tip_len])) return;
    @memcpy(tip_u16[0 .. nl + 1], new_tip[0 .. nl + 1]);
    tip_len = nl;
    var nid = std.mem.zeroes(NOTIFYICONDATAW);
    nid.cb_size = @sizeOf(NOTIFYICONDATAW);
    nid.hwnd = hwnd_ref;
    nid.uid = 1;
    nid.flags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
    nid.callback_msg = WM_USER;
    nid.hicon = tray_icon;
    @memcpy(nid.sz_tip[0 .. nl + 1], new_tip[0 .. nl + 1]);
    _ = Shell_NotifyIconW(NIM_MODIFY, &nid);
}

fn removeTray(h: ?*anyopaque) void {
    var nid = std.mem.zeroes(NOTIFYICONDATAW);
    nid.cb_size = @sizeOf(NOTIFYICONDATAW);
    nid.hwnd = h;
    nid.uid = 1;
    _ = Shell_NotifyIconW(NIM_DELETE, &nid);
}

// ---------------------------------------------------------------- tray window

const class_name: [*:0]const u16 = &[_:0]u16{ 'V', 'R', 'C', 'M', 'T' };
// Mutex + quit event are wide-char arrays (they cannot be built from `app` at
// comptime); they MUST be renamed together with `app`, or an old and a new build
// run side by side and --quit silently stops nothing.
const keeper_name: [*:0]const u16 = &[_:0]u16{ 'V', 'R', 'C', 'M', 'e', 't', 'a', 'd', 'a', 't', 'a', 'K' };
const quit_name: [*:0]const u16 = &[_:0]u16{ 'V', 'R', 'C', 'M', 'e', 't', 'a', 'd', 'a', 't', 'a', 'Q', 'u', 'i', 't' };

fn wndproc(h: ?*anyopaque, msg: u32, w: usize, l: isize) callconv(.C) isize {
    switch (msg) {
        WM_TIMER => {
            tailTick();
            scan_counter += 1;
            if (scan_counter >= 60) {
                scan_counter = 0;
                scanPhotos();
            }
            updateTooltip();
            return 0;
        },
        WM_USER, WM_CONTEXTMENU => {
            // v0 callback: lParam = mouse message id (WM_RBUTTONUP = 0x205).
            // v4 callback: lParam LOWORD = mouse message id, HIWORD = icon id;
            // wParam LOWWORD/HIGHWORD = packed x,y screen coords.
            const is_ctx = msg == WM_CONTEXTMENU;
            const ev: u32 = @intCast(@as(u64, @bitCast(l)) & 0xFFFF);
            // v4 delivers right-click as LOWORD(lParam)==WM_CONTEXTMENU, not WM_RBUTTONUP.
            if (is_ctx or ev == WM_RBUTTONUP or ev == WM_CONTEXTMENU) {
                const menu = CreatePopupMenu();
                _ = AppendMenuW(menu, MF_STRING, IDM_QUIT, &[_:0]u16{ 'Q', 'u', 'i', 't' });
                var pt = POINT{ .x = 0, .y = 0 };
                _ = GetCursorPos(&pt);
                _ = SetForegroundWindow(h);
                const cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, pt.x, pt.y, 0, h, null);
                _ = DestroyMenu(menu);
                if (cmd == IDM_QUIT) {
                    _ = KillTimer(h, TIMER_TICK);
                    removeTray(h);
                    log.write("stopped", .{});
                    log.close();
                    PostQuitMessage(0);
                }
            }
            return 0;
        },
        WM_QUERYENDSESSION => return 1,
        WM_ENDSESSION => {
            if (l != 0) removeTray(h);
            return 0;
        },
        WM_CLOSE => {
            _ = KillTimer(h, TIMER_TICK);
            removeTray(h);
            log.write("stopped", .{});
            log.close();
            PostQuitMessage(0);
            return 0;
        },
        WM_DESTROY => {
            PostQuitMessage(0);
            return 0;
        },
        else => return DefWindowProcW(h, msg, w, l),
    }
}

// ---------------------------------------------------------------- replay (tag mode)

// "YYYY-MM-DD_HH-MM-SS" as used in VRChat log file names.
// The year MUST be unsigned: with a signed argument Zig 0.14's `0>` fill emits an
// explicit sign ("+2026"), and that sorts BELOW every real file name ('+' < '0'),
// so the name cutoff stops filtering and the replay list fills with old logs.
fn logNameStamp(ep: i64, dst: *[20]u8) []const u8 {
    const c = civilFromDays(@divFloor(ep, 86400));
    const sod = @rem(ep + 86400 * 4, 86400);
    const y: u32 = @intCast(c.y);
    return std.fmt.bufPrint(dst, "{d:0>4}-{d:0>2}-{d:0>2}_{d:0>2}-{d:0>2}-{d:0>2}", .{
        y,
        c.m,
        c.d,
        @as(u8, @intCast(@rem(@divFloor(sod, 3600), 24))),
        @as(u8, @intCast(@rem(@divFloor(sod, 60), 60))),
        @as(u8, @intCast(@rem(sod, 60))),
    }) catch "";
}

fn replayLogs(stop_at: i64, window_secs: i64) void {
    // Log file names carry LOCAL wall time, and parseTs returns local-naive
    // epochs to match (see parseCreatedEpoch). The window edge must be local
    // too, or it shifts by the UTC offset.
    const cutoff = (if (stop_at != 0) stop_at else localNowEpoch()) - window_secs;
    var cutoff_name: [20]u8 = undefined;
    const cn = logNameStamp(cutoff, &cutoff_name);
    if (cn.len == 0) return;

    var pat: [PATH_U8]u8 = undefined;
    const sp = std.fmt.bufPrint(&pat, "{s}\\output_log_*.txt", .{log_dir[0..log_dir_len]}) catch return;
    _ = utf8ToU16(&u16_a, sp);
    var fd = std.mem.zeroes(WIN32_FIND_DATAW);
    const hf = FindFirstFileW(@as([*:0]u16, @ptrCast(&u16_a)), &fd);
    if (@intFromPtr(hf) == INVALID_PTR) return;
    defer _ = FindClose(hf);

    var names: [64][64]u8 = undefined;
    var lens: [64]u8 = undefined;
    var nn: usize = 0;
    var name8: [300]u8 = undefined;
    var first = true;
    while (true) {
        if (!first) {
            if (FindNextFileW(hf, &fd) == 0) break;
        }
        first = false;
        if (fd.attrs & FILE_ATTRIBUTE_DIRECTORY != 0) continue;
        const nl = nameLen(&fd);
        if (nl < 34 or nl > 63) continue;
        const l = u16ToU8(&name8, fd.name[0..nl]);
        if (l != nl) continue;
        const stamp = name8[11 .. l - 4];
        if (std.mem.lessThan(u8, stamp, cn)) continue;
        if (nn < names.len) {
            @memcpy(names[nn][0..l], name8[0..l]);
            lens[nn] = @intCast(l);
            nn += 1;
        }
    }
    for (0..nn) |i| {
        for (i + 1..nn) |j| {
            if (std.mem.lessThan(u8, names[j][0..lens[j]], names[i][0..lens[i]])) {
                std.mem.swap([64]u8, &names[i], &names[j]);
                std.mem.swap(u8, &lens[i], &lens[j]);
            }
        }
    }
    // Stop replaying as soon as a log line passes the photo's own timestamp.
    const stop: i64 = if (stop_at != 0) stop_at else 0x7FFF_FFFF_FFFF;
    for (0..nn) |i| {
        var full: [PATH_U8]u8 = undefined;
        const fp = std.fmt.bufPrint(&full, "{s}\\{s}", .{ log_dir[0..log_dir_len], names[i][0..lens[i]] }) catch continue;
        const h = openR(fp) orelse continue;
        defer _ = CloseHandle(h);
        var fsz: i64 = 0;
        if (GetFileSizeEx(h, &fsz) == 0) continue;
        var off: i64 = 0;
        var stopped = false;
        while (off < fsz and !stopped) {
            const want: u32 = @intCast(@min(@as(i64, rbuf.len), fsz - off));
            if (SetFilePointerEx(h, off, null, 0) == 0) break;
            var got: u32 = 0;
            if (ReadFile(h, &rbuf, want, &got, null) == 0 or got == 0) break;
            off += got;
            if (!feedBytes(rbuf[0..got], null, stop)) stopped = true;
        }
        if (stopped) break;
        @memcpy(live_name[0..lens[i]], names[i][0..lens[i]]);
        live_name_len = lens[i];
        live_off = fsz;
    }
    // The shared line buffer may hold a trailing partial line; the live tail
    // must start clean or it would glue it onto the next log line.
    line_buf_len = 0;
}

fn epochToIso(ep: i64, dst: *[24]u8) void {
    const days = @divFloor(ep, 86400);
    const sod = ep - days * 86400;
    const c = civilFromDays(days);
    const y: u32 = @intCast(c.y);
    const h: u8 = @intCast(@rem(@divFloor(sod, 3600), 24));
    const m: u8 = @intCast(@rem(@divFloor(sod, 60), 60));
    const s: u8 = @intCast(@rem(sod, 60));
    _ = std.fmt.bufPrint(dst, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.000Z", .{ y, c.m, c.d, h, m, s }) catch {};
}

// Local wall-clock epoch, i.e. what a VRChat log line or an XMP CreateDate in
// the same zone would parse to. Everything the app compares against times
// (log stamps, the replay cutoff) lives in this frame — nowEpoch() returned
// true UTC and silently shifted the window by the UTC offset.
fn localNowEpoch() i64 {
    var st: SYSTEMTIME = undefined;
    GetLocalTime(&st);
    return daysFromCivil(st.year, @intCast(st.month), @intCast(st.day)) * 86400 +
        @as(i64, st.hour) * 3600 + @as(i64, st.minute) * 60 + st.second;
}

// ---------------------------------------------------------------- headless mode

// Console build: same tagging engine, no window and no message loop, and no
// output of any kind — it writes nothing but the metadata in the photos. The 1 Hz
// tick is a wait on a named event, so `VRCMetadata.exe --quit` stops a running
// instance from anywhere. Nothing here touches user32/shell32/gdi32 or log.zig.
fn headlessRun() void {
    _ = CreateMutexW(null, 1, keeper_name) orelse return; // cannot guard -> do not run a second tail
    if (GetLastError() == 183) return; // ERROR_ALREADY_EXISTS: one tail is enough
    const quit = CreateEventW(null, 1, 0, quit_name) orelse return;

    var ft: FILETIME = undefined;
    GetSystemTimeAsFileTime(&ft);
    if (ftU64(ft) > 60 * 10_000_000) start_filetime = ftU64(ft) - (60 * 10_000_000);

    replayLogs(0, 86400); // seed roster from last 24h of logs

    while (true) {
        const r = WaitForSingleObject(quit, 1000);
        if (r == WAIT_OBJECT_0 or r == WAIT_FAILED) break;
        tailTick();
        scan_counter += 1;
        if (scan_counter >= 60) {
            scan_counter = 0;
            scanPhotos();
        }
    }
}

fn requestQuit() bool {
    const ev = OpenEventW(EVENT_MODIFY_STATE, 0, quit_name) orelse return false;
    defer _ = CloseHandle(ev);
    return SetEvent(ev) != 0;
}

// ---------------------------------------------------------------- main

pub fn main() void {
    if (!resolveDirs()) {
        std.debug.print("failed to resolve dirs\n", .{});
        return;
    }

    const argv_arena = std.heap.page_allocator;
    const argv_list = std.process.argsAlloc(argv_arena) catch return;
    const a1: []const u8 = if (argv_list.len > 1) argv_list[1] else "";
    const a2: []const u8 = if (argv_list.len > 2) argv_list[2] else "";

    if (std.mem.eql(u8, a1, "--tag")) {
        if (a2.len == 0) {
            std.debug.print("usage: {s} --tag <photo.png>\n", .{app});
            std.process.exit(1);
        }
        var meta = PhotoMeta{};
        if (!readPhotoChunks(a2, &meta)) {
            std.debug.print("cannot read PNG/XMP (lasterr={d} has_xmp={} has_desc={} path_len={d})\n", .{ GetLastError(), meta.has_xmp, meta.has_description, a2.len });
            std.process.exit(1);
        }
        var rep = meta.created_epoch;
        if (rep == 0) rep = localNowEpoch();
        replayLogs(rep, 259200);
        const res2 = tagPhoto(a2, session.players[0..session.nplayers], true);
        std.debug.print("tagged={}\n", .{res2 == .tagged});
        if (res2 != .tagged) std.process.exit(1);
        return;
    }

    if (std.mem.eql(u8, a1, "--quit")) {
        if (!requestQuit()) std.process.exit(1); // 1 = no headless instance was running
        return;
    }

    if (headless) headlessRun() else trayRun();
}

fn trayRun() void {
    // Single-instance guard: a second manual launch used to leave two tray
    // icons tailing the same logs side by side (proven: two live processes).
    // The --tag path above intentionally bypasses this for manual backfill.
    _ = CreateMutexW(null, 1, keeper_name) orelse return; // cannot guard -> do not run a second tail
    if (GetLastError() == 183) return; // ERROR_ALREADY_EXISTS
    var ft: FILETIME = undefined;
    GetSystemTimeAsFileTime(&ft);
    if (ftU64(ft) > 60 * 10_000_000) {
        start_filetime = ftU64(ft) - (60 * 10_000_000); // 60s grace for photos from just before start
    }

    // Tray-only status log. The headless build writes nothing, anywhere.
    openStatusLog();
    var ts: [24]u8 = undefined;
    epochToIso(localNowEpoch(), &ts); // local wall time, same frame as the metadata
    log.write("{s} {s}", .{ ts[0..19], app });
    log.write("  logs   {s}", .{log_dir[0..log_dir_len]});
    log.write("  photos {s}", .{photo_dir[0..photo_dir_len]});

    replayLogs(0, 86400); // seed roster from last 24h of logs
    log.write("  roster {d} player(s) in {s}", .{ session.nplayers, session.world_id[0..session.world_id_len] });

    const hinst = GetModuleHandleW(null);
    const wc = WNDCLASSW{
        .style = 0,
        .lpfn_wnd_proc = wndproc,
        .cb_cls_extra = 0,
        .cb_wnd_extra = 0,
        .hinstance = hinst,
        .hicon = null,
        .hcursor = null,
        .hbr_background = @ptrFromInt(3),
        .lpsz_menu_name = null,
        .lpsz_class_name = class_name,
        .hicon_sm = null,
    };
    if (RegisterClassW(&wc) == 0) {
        log.write("RegisterClassW failed err={d}", .{GetLastError()});
        return;
    }
    const hwnd = CreateWindowExW(0, class_name, class_name, WS_POPUP, CW_USEDEFAULT, CW_USEDEFAULT, 0, 0, null, null, hinst, null);
    if (hwnd == null) {
        log.write("CreateWindowExW failed err={d}", .{GetLastError()});
        return;
    }
    hwnd_ref = hwnd;
    // Custom tray icon: 16 px bin for standard DPI, 32 px bin otherwise
    // (Windows scales it down); fall back to the generic app icon on any
    // GDI failure. Measured cost: ~+1.2 MB private WS (GDI client init).
    const sm = GetSystemMetrics(49); // SM_CXSMICON
    if (sm != 0 and sm <= 20) tray_icon = makeIconFromBin(16, ICON16[0..]);
    if (tray_icon == null) tray_icon = makeIconFromBin(32, ICON32[0..]);
    if (tray_icon == null) tray_icon = LoadIconW(null, @ptrFromInt(IDI_APPLICATION));

    var nid = std.mem.zeroes(NOTIFYICONDATAW);
    nid.cb_size = @sizeOf(NOTIFYICONDATAW);
    nid.hwnd = hwnd;
    nid.uid = 1;
    nid.flags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    nid.callback_msg = WM_USER;
    nid.hicon = tray_icon;
    _ = utf8ToU16(&nid.sz_tip, app);
    if (Shell_NotifyIconW(NIM_ADD, &nid) == 0) {
        log.write("tray add failed err={d}", .{GetLastError()});
    }
    // Win10/11: opt into NOTIFYICON_VERSION_4. Without an explicit version the
    // Windows 11 hidden-icons flyout never delivers right-click notifications.
    nid.flags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
    nid.u_timeout = NOTIFYICON_VERSION_4; // same union slot as uVersion
    if (Shell_NotifyIconW(NIM_SETVERSION, &nid) == 0) {
        std.debug.print("tray setversion failed err={d}\n", .{GetLastError()});
    }
    _ = SetTimer(hwnd, TIMER_TICK, 1000, null);
    updateTooltip();

    var msg: MSG = undefined;
    while (GetMessageW(&msg, null, 0, 0) > 0) {
        _ = TranslateMessage(&msg);
        _ = DispatchMessageW(&msg);
    }
}

test "civilFromDays year boundaries" {
    // Dec was the broken month (mp==9 got year+1); pin it plus the Jan/Mar/leap edges.
    const cases = [_]struct { y: i64, m: u8, d: u8 }{
        .{ .y = 2026, .m = 12, .d = 1 }, // mp==9 boundary
        .{ .y = 2026, .m = 12, .d = 31 },
        .{ .y = 2027, .m = 1, .d = 1 }, // mp==10 boundary
        .{ .y = 2026, .m = 3, .d = 1 }, // era-spine start
        .{ .y = 2024, .m = 2, .d = 29 }, // leap
        .{ .y = 1970, .m = 1, .d = 1 },
    };
    for (cases) |c| {
        const r = civilFromDays(daysFromCivil(c.y, c.m, c.d));
        try std.testing.expectEqual(c.y, r.y);
        try std.testing.expectEqual(c.m, r.m);
        try std.testing.expectEqual(c.d, r.d);
    }
    var day = daysFromCivil(2026, 12, 1);
    while (day <= daysFromCivil(2026, 12, 31)) : (day += 1) {
        const r = civilFromDays(day);
        try std.testing.expectEqual(@as(i64, 2026), r.y);
    }
}

// ---------------------------------------------------------------- tag tests

fn mkPlayer(id: []const u8, name: []const u8) Player {
    var p = Player{};
    @memcpy(p.id[0..id.len], id);
    p.id_len = @intCast(id.len);
    @memcpy(p.name[0..name.len], name);
    p.name_len = @intCast(name.len);
    return p;
}

const PNG_SIG = "\x89PNG\r\n\x1a\n";
const PNG_IHDR = [_]u8{ 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0 };

fn pngChunkInto(dst: []u8, off: usize, ty: []const u8, body: []const u8) usize {
    std.mem.writeInt(u32, dst[off..][0..4], @intCast(body.len), .big);
    @memcpy(dst[off + 4 .. off + 8], ty);
    @memcpy(dst[off + 8 .. off + 8 + body.len], body);
    const c = crc32(dst[off + 4 .. off + 8 + body.len]);
    std.mem.writeInt(u32, dst[off + 8 + body.len ..][0..4], c, .big);
    return off + 12 + body.len;
}

// Walks the real file's chunks: verifies EVERY CRC, counts iTXt Description
// chunks, captures the first JSON, records which chunk index it landed at.
fn readDescChunks(name: []const u8, out: []u8) !struct { n: usize, json_len: usize, first_idx: usize } {
    const data = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, name, 1 << 20);
    defer std.heap.page_allocator.free(data);
    try std.testing.expectEqualStrings(PNG_SIG, data[0..8]);
    var off: usize = 8;
    var idx: usize = 0;
    var n: usize = 0;
    var json_len: usize = 0;
    var first_idx: usize = 0xFFFF;
    while (off + 12 <= data.len) {
        const clen = std.mem.readInt(u32, data[off..][0..4], .big);
        if (off + 12 + clen > data.len) return error.TruncatedChunk;
        const ty = data[off + 4 .. off + 8];
        const body = data[off + 8 .. off + 8 + clen];
        const crc_at = std.mem.readInt(u32, data[off + 8 + clen ..][0..4], .big);
        try std.testing.expectEqual(crc32(data[off + 4 .. off + 8 + clen]), crc_at); // chunk CRC must be valid
        if (std.mem.eql(u8, ty, "iTXt")) {
            const nul = std.mem.indexOfScalar(u8, body, 0) orelse 0;
            if (std.mem.eql(u8, body[0..nul], "Description")) {
                n += 1;
                if (n == 1) {
                    first_idx = idx;
                    json_len = @min(body.len - nul - 5, out.len);
                    @memcpy(out[0..json_len], body[nul + 5 ..][0..json_len]);
                }
            }
        }
        idx += 1;
        if (std.mem.eql(u8, ty, "IEND")) break;
        off += 12 + clen;
    }
    return .{ .n = n, .json_len = json_len, .first_idx = first_idx };
}

test "buildJson writes valid VRCX-compatible JSON (world object must close)" {
    var meta = PhotoMeta{};
    const a_id = "usr_self0";
    const a_nm = "Self";
    const w_id = "wrld_abcd";
    const w_nm = "World";
    @memcpy(meta.author_id[0..a_id.len], a_id);
    meta.author_id_len = @intCast(a_id.len);
    @memcpy(meta.author_name[0..a_nm.len], a_nm);
    meta.author_name_len = @intCast(a_nm.len);
    @memcpy(meta.world_id[0..w_id.len], w_id);
    meta.world_id_len = @intCast(w_id.len);
    @memcpy(meta.world_name[0..w_nm.len], w_nm);
    meta.world_name_len = @intCast(w_nm.len);
    var players = [_]Player{mkPlayer("usr_b", "Buddy")};
    const json = buildJson(&meta, "inst-1", &players, null, "2026-11-04T11:14:18.000Z");
    const want = "{\"application\":\"VRCPicTag\",\"version\":1," ++
        "\"author\":{\"id\":\"usr_self0\",\"displayName\":\"Self\"}," ++
        "\"world\":{\"id\":\"wrld_abcd\",\"name\":\"World\",\"instanceId\":\"inst-1\"}," ++ // },\"players\" regression: 2026-11-05 break
        "\"players\":[{\"id\":\"usr_b\",\"displayName\":\"Buddy\"}]," ++
        "\"timestamp\":\"2026-11-04T11:14:18.000Z\"}";
    try std.testing.expectEqualStrings(want, json);
}

test "writeDescriptionChunk: inserts, replaces old (no dupes), CRCs valid" {
    var png: [8 + 25 + 12]u8 = undefined;
    @memcpy(png[0..8], PNG_SIG);
    const o = pngChunkInto(&png, 8, "IHDR", &PNG_IHDR);
    _ = pngChunkInto(&png, o, "IEND", "");
    std.fs.cwd().deleteFile("vrctag_t1.png") catch {};
    const f = std.fs.cwd().createFile("vrctag_t1.png", .{}) catch return error.TestUnexpectedResult;
    f.writeAll(&png) catch {};
    f.close();
    try std.testing.expect(writeDescriptionChunk("vrctag_t1.png", "{\"n\":1}"));
    var out: [256]u8 = undefined;
    const r1 = try readDescChunks("vrctag_t1.png", &out);
    try std.testing.expectEqual(@as(usize, 1), r1.n);
    try std.testing.expectEqual(@as(usize, 1), r1.first_idx); // right after IHDR
    try std.testing.expectEqualStrings("{\"n\":1}", out[0..r1.json_len]);
    try std.testing.expect(writeDescriptionChunk("vrctag_t1.png", "{\"n\":2}")); // old must be dropped, not duplicated
    const r2 = try readDescChunks("vrctag_t1.png", &out);
    try std.testing.expectEqual(@as(usize, 1), r2.n);
    try std.testing.expectEqualStrings("{\"n\":2}", out[0..r2.json_len]);
    std.fs.cwd().deleteFile("vrctag_t1.png") catch {};
}

test "tagPhoto end-to-end: session world mismatch strips instance+roster, match keeps both" {
    const xmp = "<x:vrc><vrc:WorldID>wrld_photo</vrc:WorldID>" ++
        "<vrc:WorldDisplayName>Real World</vrc:WorldDisplayName>" ++
        "<vrc:AuthorID>usr_self0</vrc:AuthorID>" ++
        "<xmp:Author>Self</xmp:Author>" ++
        "<xmp:CreateDate>2026-11-04T11:14:18.000+01:00</xmp:CreateDate></x:vrc>";
    const kw = "XML:com.adobe.xmp";
    const body_len = kw.len + 1 + xmp.len;
    var png: [8 + 25 + 12 + body_len + 12]u8 = undefined;
    @memcpy(png[0..8], PNG_SIG);
    var o = pngChunkInto(&png, 8, "IHDR", &PNG_IHDR);
    var tb: [body_len]u8 = undefined;
    @memcpy(tb[0..kw.len], kw);
    tb[kw.len] = 0;
    @memcpy(tb[kw.len + 1 ..], xmp);
    o = pngChunkInto(&png, o, "tEXt", &tb);
    _ = pngChunkInto(&png, o, "IEND", "");
    std.fs.cwd().deleteFile("vrctag_t2.png") catch {};
    const f = std.fs.cwd().createFile("vrctag_t2.png", .{}) catch return error.TestUnexpectedResult;
    f.writeAll(&png) catch {};
    f.close();

    // Session points at a DIFFERENT world: instanceId/roster must not leak in.
    session.resetWorld("wrld_other", "inst-wrong");
    session.join("Buddy", "usr_bud");
    const r1 = tagPhoto("vrctag_t2.png", session.players[0..session.nplayers], false);
    try std.testing.expectEqual(TagResult.tagged, r1);
    var out: [4096]u8 = undefined;
    const c1 = try readDescChunks("vrctag_t2.png", &out);
    try std.testing.expectEqual(@as(usize, 1), c1.n);
    const want_mismatch = "{\"application\":\"VRCPicTag\",\"version\":1," ++
        "\"author\":{\"id\":\"usr_self0\",\"displayName\":\"Self\"}," ++
        "\"world\":{\"id\":\"wrld_photo\",\"name\":\"Real World\",\"instanceId\":\"\"}," ++
        "\"players\":[{\"id\":\"usr_self0\",\"displayName\":\"Self\"}]," ++ // author-only, no Buddy, no wrong instance
        "\"timestamp\":\"2026-11-04T11:14:18.000Z\"}";
    try std.testing.expectEqualStrings(want_mismatch, out[0..c1.json_len]);

    // Session matches the photo world: full roster + instance id.
    session.resetWorld("wrld_photo", "inst-photo");
    session.join("Buddy", "usr_bud");
    const r2 = tagPhoto("vrctag_t2.png", session.players[0..session.nplayers], true);
    try std.testing.expectEqual(TagResult.tagged, r2);
    const c2 = try readDescChunks("vrctag_t2.png", &out);
    try std.testing.expectEqual(@as(usize, 1), c2.n);
    const want_match = "{\"application\":\"VRCPicTag\",\"version\":1," ++
        "\"author\":{\"id\":\"usr_self0\",\"displayName\":\"Self\"}," ++
        "\"world\":{\"id\":\"wrld_photo\",\"name\":\"Real World\",\"instanceId\":\"inst-photo\"}," ++
        "\"players\":[{\"id\":\"usr_bud\",\"displayName\":\"Buddy\"},{\"id\":\"usr_self0\",\"displayName\":\"Self\"}]," ++
        "\"timestamp\":\"2026-11-04T11:14:18.000Z\"}";
    try std.testing.expectEqualStrings(want_match, out[0..c2.json_len]);
    std.fs.cwd().deleteFile("vrctag_t2.png") catch {};
}

test "tailTick: non-ASCII output_log_* name skipped (64-byte name buffers)" {
    // 45 chars but 105 UTF-8 bytes: without the byte guard the memcpy into the
    // 64-byte best/live_name buffers overflows (panic = silent tray death).
    const nm = "output_log_" ++ "\u{3042}" ** 30 ++ ".txt";
    std.fs.cwd().deleteFile(nm) catch {};
    const f = std.fs.cwd().createFile(nm, .{}) catch return error.TestUnexpectedResult;
    f.close();
    log_dir[0] = '.';
    log_dir_len = 1;
    live_name_len = 0;
    tailTick(); // guard: file skipped, best_len stays 0
    std.fs.cwd().deleteFile(nm) catch {};
}

test "updateTooltip: replacement tip is NUL-terminated (no stale u16 from a longer old tip)" {
    // Shell_NotifyIconW just fails against a bogus hwnd, but the tip buffers
    // are written before the Shell call, so the write path is still exercised.
    // The var function pointer forces a real call: both calls share one stack
    // frame, so an uninitialized new_tip[nl] carries residue from the first
    // (longer) tip instead of a guaranteed NUL.
    var call: *const fn () void = &updateTooltip;
    _ = &call; // keep address-taken: no inlining, both calls share one frame
    hwnd_ref = @ptrFromInt(1);
    defer hwnd_ref = null;
    tip_len = 0;
    session.world_id_len = 9;
    @memcpy(session.world_id[0..9], "VRCMetada"); // any id works: this test only checks NUL termination
    session.last_world_name_len = 0;
    session.nplayers = 0;
    call(); // tip = 9 chars
    session.world_id_len = 3;
    @memcpy(session.world_id[0..3], "Cat");
    call(); // nl=3: the (nl+1)-copy must land NUL at index 3, not 'P' from the first tip
    try std.testing.expect(tip_u16[3] == 0);
}

// ---------------------------------------------------------------- buffer/encoding tests

var cam_hits: usize = 0;
fn camCount() void {
    cam_hits += 1;
}

test "feedBytes: live mode fires the camera callback per line, replay stops at stop_at" {
    const stream = "2026.11.16 10:00:00 Log        -  [Behaviour] Joining wrld_x:1\n" ++
        "2026.11.16 10:00:01 Log        -  [Behaviour] OnPlayerJoined Buddy (usr_bud)\n" ++
        "2026.11.16 10:00:02 Log        -  [VRC Camera] Took screenshot to: C:\\a.png\n" ++
        "2026.11.16 10:00:03 Log        -  [VRC Camera] Took screenshot to: C:\\b.png\n";

    session = Session{};
    line_buf_len = 0;
    cam_hits = 0;
    try std.testing.expect(feedBytes(stream, &camCount, 0)); // live: never bails
    try std.testing.expectEqual(@as(usize, 2), cam_hits);
    try std.testing.expectEqualStrings("wrld_x", session.world_id[0..session.world_id_len]);
    try std.testing.expectEqual(@as(u16, 1), session.nplayers);
    try std.testing.expectEqualStrings("C:\\b.png", camera_path[0..camera_path_len]);

    // Replay: stops as soon as a line passes the photo time, and never fires the
    // camera callback (that is what would tag during a backfill).
    session = Session{};
    line_buf_len = 0;
    cam_hits = 0;
    const stop = parseTs("2026.11.16 10:00:01").?;
    try std.testing.expect(!feedBytes(stream, &camCount, stop));
    try std.testing.expectEqual(@as(usize, 0), cam_hits);
    try std.testing.expectEqualStrings("wrld_x", session.world_id[0..session.world_id_len]);
    try std.testing.expectEqual(@as(u16, 1), session.nplayers);
    session = Session{};
}

test "u16ToU8 joins surrogate pairs into one 4-byte UTF-8 sequence" {
    // A non-BMP char (U+1F3AE) used to be emitted as CESU-8, which utf8ToU16
    // read back as six U+FFFD: every path holding one was corrupted.
    const w = [_]u16{ 'C', ':', 0xD83C, 0xDFAE, 0 };
    var out: [32]u8 = undefined;
    const n = u16ToU8(&out, &w);
    try std.testing.expectEqual(@as(usize, 6), n);
    try std.testing.expect(std.unicode.utf8ValidateSlice(out[0..n]));
    try std.testing.expectEqualStrings("C:\xF0\x9F\x8E\xAE", out[0..n]);
    var back: [16]u16 = undefined;
    const m = utf8ToU16(&back, out[0..n]);
    try std.testing.expectEqualSlices(u16, w[0..4], back[0..m]);
}

test "buildJson returns empty instead of truncated JSON when the roster overflows" {
    var meta = PhotoMeta{};
    @memcpy(meta.author_id[0..7], "usr_me0");
    meta.author_id_len = 7;
    var name256: [256]u8 = undefined;
    @memset(&name256, '"'); // 6 escaped bytes per input byte: guaranteed overflow
    var players: [MAX_PLAYERS]Player = undefined;
    for (&players) |*p| p.* = mkPlayer("usr_p0000", &name256);
    const json = buildJson(&meta, "inst", &players, null, "2026-11-16T10:00:00.000Z");
    try std.testing.expectEqual(@as(usize, 0), json.len);
}

test "an overlong log line is dropped without corrupting the next one" {
    // line_buf is 16 KiB; a line past that is truncated at the newline exactly the
    // way a 256 KiB buffer truncated a 256 KiB line, and the stream resyncs.
    var stream = std.ArrayList(u8).init(std.testing.allocator);
    defer stream.deinit();
    try stream.appendNTimes('x', 20000);
    try stream.appendSlice("\n2026.11.16 10:00:00 Log        -  [Behaviour] Joining wrld_ok:1~region(eu)\n");
    try stream.appendSlice("2026.11.16 10:00:01 Log        -  [VRC Camera] Took screenshot to: C:\\ok.png\n");

    session = Session{};
    line_buf_len = 0;
    try std.testing.expect(feedBytes(stream.items, null, 0));
    try std.testing.expectEqualStrings("wrld_ok", session.world_id[0..session.world_id_len]);
    try std.testing.expectEqualStrings("C:\\ok.png", camera_path[0..camera_path_len]);
    session = Session{};
}

test "buildJson fits a full 80-player instance" {
    // Right-sized json_buf: a realistic public-instance roster must NOT hit the
    // overflow path (which silently skips tagging).
    var meta = PhotoMeta{};
    @memcpy(meta.world_id[0..8], "wrld_fit");
    meta.world_id_len = 8;
    var long_name: [40]u8 = undefined;
    @memset(&long_name, 'x');
    var players: [80]Player = undefined;
    for (&players) |*pl| pl.* = mkPlayer("usr_0123456789abcdef0123456789abcdef01234", &long_name);
    const json = buildJson(&meta, "12345~region(eu)", &players, null, "2026-11-16T10:00:00.000Z");
    try std.testing.expect(json.len > 0);
    try std.testing.expect(json.len < json_buf.len);
}

test "localNowEpoch matches the local wall clock" {
    const ep = localNowEpoch();
    var st: SYSTEMTIME = undefined;
    GetLocalTime(&st);
    const again = daysFromCivil(st.year, @intCast(st.month), @intCast(st.day)) * 86400 +
        @as(i64, st.hour) * 3600 + @as(i64, st.minute) * 60 + st.second;
    try std.testing.expect(@abs(again - ep) <= 2); // would fail by the UTC offset if it read UTC
}

test "time stamps render zero-padded with no sign (signed `0>` fill emits '+')" {
    const ep = parseTs("2026.11.16 12:34:56").?;
    var iso: [24]u8 = undefined;
    epochToIso(ep, &iso);
    try std.testing.expectEqualStrings("2026-11-16T12:34:56.000Z", &iso);
    var nm: [20]u8 = undefined;
    try std.testing.expectEqualStrings("2026-11-16_12-34-56", logNameStamp(ep, &nm));
}

test "replayLogs: stale logs are filtered by name, so the newest log still replays" {
    // Regression: the cutoff stamp rendered as "+2026-..." (signed year, `0>` fill),
    // which sorts below every real file name. With >= 64 log files in the VRChat
    // dir, all replay slots went to old logs and the roster/instance came out empty.
    const dir = "vrctag_logs";
    std.fs.cwd().deleteTree(dir) catch {};
    try std.fs.cwd().makeDir(dir);
    defer std.fs.cwd().deleteTree(dir) catch {};
    for (0..70) |i| {
        var nm: [64]u8 = undefined;
        const n = try std.fmt.bufPrint(&nm, "{s}\\output_log_2020-01-01_00-00-{d:0>2}.txt", .{ dir, @as(u8, @intCast(i)) });
        const f = try std.fs.cwd().createFile(n, .{});
        f.close();
    }
    const real = try std.fs.cwd().createFile(dir ++ "\\output_log_2026-11-16_10-00-00.txt", .{});
    real.writeAll("2026.11.16 10:00:00 Log        -  [Behaviour] Joining wrld_t:1~region(eu)\n" ++
        "2026.11.16 10:00:01 Log        -  [Behaviour] OnPlayerJoined Pal (usr_pal)\n") catch {};
    real.close();

    session = Session{};
    live_name_len = 0;
    const sp = try std.fmt.bufPrint(&log_dir, "{s}", .{dir});
    log_dir_len = sp.len;
    defer {
        log_dir_len = 1;
        log_dir[0] = '.';
        live_name_len = 0;
        line_buf_len = 0;
        session = Session{};
    }
    replayLogs(parseTs("2026.11.16 10:00:05").?, 259200);
    try std.testing.expectEqualStrings("wrld_t", session.world_id[0..session.world_id_len]);
    try std.testing.expectEqual(@as(u16, 1), session.nplayers);
}
