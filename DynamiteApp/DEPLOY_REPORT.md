# Deploy report — Dynamite

**Date:** 2026-07-20  
**Task:** task_2fab0e5cbf25  
**Dispatch:** ctx_00ddefdc01e7

## Build

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Dynamite.xcodeproj -scheme Dynamite -configuration Debug \
  -destination platform=macOS -derivedDataPath /tmp/pocket-dd build
```

**Result:** `** BUILD SUCCEEDED **`  
Derived data: `/tmp/pocket-dd/Build/Products/Debug/Dynamite.app`

### Build tail
```
RegisterWithLaunchServices /tmp/pocket-dd/Build/Products/Debug/Dynamite.app
note: Disabling hardened runtime with ad-hoc codesigning. (in target 'Dynamite' from project 'Dynamite')
** BUILD SUCCEEDED **
```

(Pre-existing Swift concurrency warnings only; no errors.)

## Install

1. `pkill -x Dynamite`
2. `rm -rf /Applications/Dynamite.app && ditto /tmp/pocket-dd/Build/Products/Debug/Dynamite.app /Applications/Dynamite.app`
3. `open /Applications/Dynamite.app`

## Runtime verification

| Check | Result |
|-------|--------|
| Alive ≥5s | **OK** — PID 57927 still running after sleep 5 |
| Binary path | **OK** — `/Applications/Dynamite.app/Contents/MacOS/Dynamite` |

### Process evidence
```
PID 57927  /Applications/Dynamite.app/Contents/MacOS/Dynamite
lsof txt:  /Applications/Dynamite.app/Contents/MacOS/Dynamite
XPC:       /Applications/Dynamite.app/Contents/XPCServices/DynamiteXPCHelper.xpc/...
adapter:   .../Dynamite.app/Contents/Resources/mediaremote-adapter.pl
```

**PATH_OK** — process runs from `/Applications`, not derivedData.
