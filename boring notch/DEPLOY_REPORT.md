# Deploy report — boringNotch

**Date:** 2026-07-20  
**Task:** task_2fab0e5cbf25  
**Dispatch:** ctx_00ddefdc01e7

## Build

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug \
  -destination platform=macOS -derivedDataPath /tmp/pocket-dd build
```

**Result:** `** BUILD SUCCEEDED **`  
Derived data: `/tmp/pocket-dd/Build/Products/Debug/boringNotch.app`

### Build tail
```
RegisterWithLaunchServices /tmp/pocket-dd/Build/Products/Debug/boringNotch.app
note: Disabling hardened runtime with ad-hoc codesigning. (in target 'boringNotch' from project 'boringNotch')
** BUILD SUCCEEDED **
```

(Pre-existing Swift concurrency warnings only; no errors.)

## Install

1. `pkill -x boringNotch`
2. `rm -rf /Applications/boringNotch.app && ditto /tmp/pocket-dd/Build/Products/Debug/boringNotch.app /Applications/boringNotch.app`
3. `open /Applications/boringNotch.app`

## Runtime verification

| Check | Result |
|-------|--------|
| Alive ≥5s | **OK** — PID 57927 still running after sleep 5 |
| Binary path | **OK** — `/Applications/boringNotch.app/Contents/MacOS/boringNotch` |

### Process evidence
```
PID 57927  /Applications/boringNotch.app/Contents/MacOS/boringNotch
lsof txt:  /Applications/boringNotch.app/Contents/MacOS/boringNotch
XPC:       /Applications/boringNotch.app/Contents/XPCServices/BoringNotchXPCHelper.xpc/...
adapter:   .../boringNotch.app/Contents/Resources/mediaremote-adapter.pl
```

**PATH_OK** — process runs from `/Applications`, not derivedData.
