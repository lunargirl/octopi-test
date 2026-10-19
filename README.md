# Octopi

iPhone app that records a walk from Core Motion (steps + heading) and draws the path live.

**Location:** `~/Desktop/stuff/lamb`  
**Bundle ID:** `com.lunahudman.NavigationApp`  
**Minimum iOS:** 17.0  
**PR:** https://github.com/lunargirl/stuff/pull/2

## What it does

1. Tap **Start** — Core Motion feeds a step detector and dead reckoner.
2. Walk — a 2D trail updates on the canvas (green = start, orange = you).
3. Optional **Pin** — mark the current spot on the path.
4. Tap **Stop**.

## Layout

```
lamb/
├── App/           app entry
├── AppModel/      Recorder (wires sensors → path)
├── Sensors/       IMUSample, MotionManager
├── Tracking/      steps, heading, dead reckoning, trajectory
├── Views/         Home (canvas + controls), PathCanvas
└── Tests/         step + PDR unit tests
```

## Build

```bash
cd ~/Desktop/stuff/lamb
xcodebuild -project NavigationApp.xcodeproj \
  -scheme NavigationApp \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Physical iPhone recommended for real steps.
