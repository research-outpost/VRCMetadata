# VRCMetadata

A small Windows tool that adds session metadata to your VRChat screenshots: the
world, its instance, who was in it, and when the photo was taken.

**VRCMetadata is a standalone alternative for people who don't use VRCX**

It works from local sources only: the photo's own XMP, and VRChat's log files in
`%USERPROFILE%\AppData\LocalLow\VRChat\VRChat`. No VRChat API, no account, no
network access.

What it writes, into the PNG's `iTXt` `Description` chunk as VRCX-compatible JSON:

```json
{"application":"VRCPicTag","version":1,
 "author":{"id":"usr_...","displayName":"..."},
 "world":{"id":"wrld_...","name":"...","instanceId":"..."},
 "players":[{"id":"usr_...","displayName":"..."}],
 "timestamp":"2026-11-16T20:00:00.000Z"}
```

## The executables

| Name | What it does | Estimated RAM usage |
|---|---|---|
| **`VRCMetadata.exe`** | Headless and silent. | 0.3 MB |
| **`VRCMetadata-gui.exe`** | Includes a tray icon showing the current information, with right-click Quit. | 0.4 MB |

Both enforce a single instance with the same mutex, so run one or the other. Only
one is ever needed: pick headless for the smallest footprint, tray if you want to
see what it is doing.

`VRCPIC_LOGDIR` and `VRCPIC_PHOTODIR` override the default log and photo folders.

## Build

Zig 0.14.1, from this folder:

```
zig build-exe console_main.zig -O ReleaseSmall --subsystem windows -femit-bin=VRCMetadata.exe
zig build-exe main.zig         -O ReleaseSmall --subsystem windows -femit-bin=VRCMetadata-gui.exe
```

## Licence

MIT.
