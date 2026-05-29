# Xcode Project Setup — Handoff for Claude Code

**Status:** SessionKit Swift Package (Build Phase 1) is complete and committed.
The Xcode project wrapper does not exist yet. This document is your complete
instruction set to create it. Do not deviate from the structure described here.

---

## Environment Requirements

- Xcode 15.0+ (Swift 5.9+ required — `Package.swift` declares `swift-tools-version: 5.9`)
- iOS 16 minimum deployment target
- No third-party dependencies at v1

Verify before starting:
```bash
xcodebuild -version        # must be Xcode 15.x or later
swift --version            # must be Swift 5.9.x or later
xcode-select -p            # must point to Xcode.app, not CommandLineTools
```

---

## Repository Layout (current)

```
FableSignal/
├── CLAUDE.md                        ← operating contract (do not alter)
├── XCODE_SETUP.md                   ← this file
└── SessionKit/                      ← Swift Package, Build Phase 1 complete
    ├── Package.swift
    ├── Sources/SessionKit/
    │   ├── SessionModel.swift
    │   ├── CurveEvaluator.swift
    │   └── SessionScheduler.swift
    └── Tests/SessionKitTests/
        ├── CurveEvaluatorTests.swift
        ├── SessionModelTests.swift
        └── SessionSchedulerTests.swift
```

---

## Target Layout After This Task

```
FableSignal/
├── CLAUDE.md
├── XCODE_SETUP.md
├── FableSignal.xcodeproj/           ← CREATE THIS
├── FableSignal/                     ← app target source root
│   ├── App/
│   │   ├── FableSignalApp.swift
│   │   └── ContentView.swift        ← stub only
│   └── Resources/
│       └── Assets.xcassets/
└── SessionKit/                      ← unchanged Swift Package
```

---

## Step-by-Step Instructions

### Step 1 — Create the Xcode project via CLI

```bash
cd /path/to/FableSignal

# Generate a minimal iOS app project using xcodebuild scaffolding.
# We use the template approach: create via Xcode's built-in project template.
# The cleanest CLI method is xcodegen if available; otherwise use the
# script below which constructs the .xcodeproj manually.
```

**Preferred: use xcodegen (install if not present)**

```bash
brew install xcodegen
```

Create `project.yml` at the repo root:

```yaml
name: FableSignal
options:
  bundleIdPrefix: com.guthrieentertainment
  deploymentTarget:
    iOS: "16.0"
  xcodeVersion: "15.0"
  swift: "5.9"
  generateEmptyDirectories: true
targets:
  FableSignal:
    type: application
    platform: iOS
    deploymentTarget: "16.0"
    sources:
      - path: FableSignal
    dependencies:
      - package: SessionKit
    info:
      path: FableSignal/Info.plist
      properties:
        CFBundleDisplayName: FableSignal
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.guthrieentertainment.fablesignal
      SWIFT_VERSION: 5.9
      DEVELOPMENT_TEAM: ""          # fill in after device provisioning
      TARGETED_DEVICE_FAMILY: "1"   # iPhone only
packages:
  SessionKit:
    path: SessionKit
```

Then run:
```bash
xcodegen generate
```

**Fallback: manual scaffold (if xcodegen unavailable)**

See the "Manual Scaffold" section at the bottom of this file.

---

### Step 2 — Create stub app source files

Create `FableSignal/App/FableSignalApp.swift`:

```swift
import SwiftUI

@main
struct FableSignalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

Create `FableSignal/App/ContentView.swift`:

```swift
import SwiftUI

// STUB — Build Phase 5 will replace this with the full SwiftUI shell.
// Do not add logic here until SessionRunner (Phase 4) is wired.
struct ContentView: View {
    var body: some View {
        Text("FableSignal")
            .font(.largeTitle)
    }
}
```

Create `FableSignal/Resources/Assets.xcassets` — use Xcode's default
empty asset catalog (single `Contents.json` with `{"info":{"version":1,"author":"xcode"}}`).

---

### Step 3 — Verify the build

```bash
# Build for simulator (no device required at this phase)
xcodebuild \
  -project FableSignal.xcodeproj \
  -scheme FableSignal \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug \
  build

# Run SessionKit unit tests (no device required)
cd SessionKit
swift test
cd ..
```

**Both must pass clean before committing.**

If `swift test` fails with a tools-version error, your Swift version is below 5.9.
Do not proceed — resolve the toolchain first.

---

### Step 4 — Verify SessionKit is linked correctly

After the project builds:
1. In Xcode: open `FableSignal.xcodeproj`
2. Select the `FableSignal` target → General → Frameworks, Libraries, and
   Embedded Content → confirm `SessionKit` appears as a local package
3. Add `import SessionKit` to `ContentView.swift` and confirm it compiles

---

### Step 5 — Commit

```bash
git add FableSignal.xcodeproj FableSignal/ project.yml
git commit -m "build: scaffold Xcode project, stub app target, link SessionKit

- FableSignal.xcodeproj created via xcodegen
- Stub FableSignalApp + ContentView (Phase 5 placeholder)
- SessionKit linked as local Swift Package
- project.yml committed as source of truth for project structure
- xcodebuild + swift test both pass clean"
git push
```

---

## What Is NOT Your Job Here

- Do not implement AudioEngine (Phase 2)
- Do not implement StrobeController (Phase 3)
- Do not implement SessionRunner (Phase 4)
- Do not add any UI beyond the stub ContentView
- Do not add third-party packages
- Do not alter any file in SessionKit/

The only deliverable is a clean-building Xcode project with SessionKit linked
as a local package and both xcodebuild and swift test passing.

---

## Manual Scaffold (fallback — only if xcodegen unavailable)

If xcodegen cannot be installed, create the project using Xcode GUI:

1. File → New → Project → iOS → App
2. Product Name: `FableSignal`
3. Bundle ID: `com.guthrieentertainment.fablesignal`
4. Interface: SwiftUI, Language: Swift
5. Save into the `FableSignal` repo root (Xcode will create `FableSignal.xcodeproj`)
6. After creation: File → Add Package Dependencies → Add Local → select `SessionKit/`
7. Add `SessionKit` to the `FableSignal` target
8. Delete any auto-generated test targets (SessionKit has its own)
9. Verify the build and commit per Steps 3–5 above

Do not use the GUI path if xcodegen is available. project.yml is the preferred
source of truth for project structure — it keeps the .xcodeproj reproducible
and diff-readable.

---

## Open Architecture Decision (from CLAUDE.md Section 9.4)

`SoundscapeSource` — generated ambient audio vs licensed/produced audio beds —
is unresolved and blocks `SoundscapeMixer` architecture. This is a Congress
Moment. Do not begin SoundscapeMixer work until this is resolved with Marshall.

---

*This file was written by Claude (claude.ai) after auditing the full repo on
the Mac mini. It reflects the actual state of all committed source files.*
