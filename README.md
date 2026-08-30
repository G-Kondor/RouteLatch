# RouteLatch

**Stay on your route.**  
GPX Navigation for Runners

RouteLatch is a native SwiftUI iPhone and Apple Watch MVP. Import a GPX course on iPhone, inspect and persist it, set a target pace, queue a normalized copy with WatchConnectivity, then navigate independently on Apple Watch with live route deviation, pace-plan feedback, progress, haptics, heart rate, and an outdoor running workout. The Watch can also record a free run without selecting a route.

For device testing, both apps bundle `Resources/DefaultRoute.gpx` (Spartacus 2025 – Terep XL). Each app installs it into its own route store once on first launch. Deleting the seeded route does not recreate it on subsequent launches; deleting/reinstalling the app resets the seed marker.

> Imported GPX courses stay inside RouteLatch. Apple provides no public API for importing arbitrary GPX geometry into the built-in Workout app. RouteLatch records only the runner’s actual Core Location samples into a HealthKit workout route—never imported GPX points.

## Architecture

- `RouteLatch.xcodeproj`: native iOS and watchOS application targets and shared schemes.
- `Packages/RouteLatchCore`: local Swift package used by both apps. It owns Codable/Sendable route models, streaming GPX parsing, calculations, matching, hysteresis, persistence, and versioned transfer serialization.
- `iOS`: route library, security-scoped file import, document opening, route detail map, and phone-side WatchConnectivity.
- `Watch`: free runs, offline route library, receipt/persistence, map and metrics navigation, Core Location, haptics, and HealthKit workout recording.
- `WatchWidget`: an interactive Smart Stack workout widget with elapsed time, actual distance, average pace, pause/resume, and finish controls.
- `Backend`: a minimal Vercel Function that keeps the Strava client secret off the phone while exchanging and refreshing OAuth tokens.
- `Resources/DefaultRoute.gpx`: temporary first-launch test course embedded in both application bundles.

Dependencies are passed through view models and small services. Apple coordinators are wrapped outside the views. UI state is main-actor isolated, and the reusable core is `Sendable`.

## Supported GPX

The streaming Foundation `XMLParser` supports:

- `trk`, `trkseg`, and `trkpt`;
- `rte` and `rtept`;
- route/track `name`, point `ele`, and ISO-8601 `time`;
- multiple segments, route-only documents, and XML namespace prefixes.

Segment boundaries are preserved, so disconnected segments are not joined visually or in distance calculations. Coordinates are range-validated. Empty, malformed, missing-coordinate, and oversized files return user-visible errors. The default safety limit is 100,000 points (`GPXParser.defaultMaximumPointCount`). SHA-256 fingerprints detect duplicate imports.

The importer requests security-scoped access, copies the GPX into `Application Support/RouteLatch/OriginalGPX/<route-id>/`, releases external access, and parses only the app-owned copy. The original filename is preserved, and failed, duplicate, or deleted imports clean up their provenance copy. Normalized `.route` files use atomic writes under `Application Support/RouteLatch/Routes`. A corrupt route file is isolated rather than preventing all routes from loading.

Normalized transfer payloads are size-, point-, coordinate-, and schema-validated on receipt. Routes above 20,000 points are simplified per GPX segment with an iterative Ramer–Douglas–Peucker pass, starting at 3 m and never exceeding 12 m tolerance, before transfer to keep Watch rendering and matching efficient. If unusually noisy geometry cannot meet the Watch limit safely, transfer fails with a clear error instead of silently degrading guidance. The phone retains the full imported geometry.

## Route deviation and progress

`RouteMatcher` projects the current location onto route line segments in a local metre coordinate space; it does not merely select the closest stored point. It tracks the previous edge and searches an 80-edge moving window, with a full-route fallback when the local match is more than 150 m away. Spatial ties prefer continuous forward edges, which resolves common loop and out-and-back overlap ambiguity. Projection also handles antimeridian-crossing geometry. Accumulated edge distance determines progress and remaining course distance. Disconnected segment gaps are excluded.

Samples worse than 75 m horizontal accuracy are ignored. Off-course alerts enter above 40 m, clear below 25 m, and repeat no more often than every 20 seconds. Return-to-route and finish haptics are distinct, with the finish signal emitted once per guidance session. These constants live in `RouteMatcher` and `OffCourseAlertState`.

## Target pace and schedule alerts

Each route can store an optional target pace from 3:00 to 15:00 min/km in five-second steps. The iPhone route detail screen shows a slider and the planned running time. The setting travels inside the normalized route when **Send to Apple Watch** is used. Changing the phone setting marks the Watch copy as stale until it is sent again. The Watch route detail screen can also change its local copy immediately before a run without a phone.

Free Run has the same optional 3:00–15:00 min/km target and five-second slider on its Watch setup screen. The choice persists locally for later free runs. Since a free run has no planned finish distance, it shows live target pace and schedule advantage/delay but does not invent a projected finish duration.

During every run, RouteLatch calculates average pace from active workout time and the distance actually recorded by HealthKit. Until HealthKit publishes live distance, a conservative GPS accumulator supplies a temporary fallback and rejects stale, out-of-order, inaccurate, and physically implausible samples. Planned GPX distance and route-matched progress never enter the finished average-pace result, so stopping before the selected route ends cannot improve the result. Paused time is excluded.

For guided runs it also shows the target pace, schedule advantage/delay, and projected duration. To avoid noisy start alerts, pace warnings become eligible only after 500 m and three active minutes. The Watch enters a yellow **BEHIND GOAL** state and plays a pace haptic when average pace is more than 10% slower than the target, clears after recovering to within 5%, and repeats at most every two minutes. A red off-course warning always takes visual and haptic priority.

The first in-app workout page follows the compact Fitness/Health-style layout: live elapsed time, actual distance, average pace, and large pause/resume and finish controls remain together. The optional **RouteLatch Live Run** rectangular widget can be added to the Watch Smart Stack for the same metrics and controls without finding the app. Widget commands are passed only to the currently active workout and stale widget state expires automatically.

## Required capabilities and privacy

Both targets use Apple Developer team `595EKYS652` with automatic signing and these checked-in identifiers:

- iPhone: `com.gergokondor.RouteLatchApp`
- Watch: `com.gergokondor.RouteLatchApp.watchkitapp`
- Watch companion: `com.gergokondor.RouteLatchApp`

Separate opaque App Store icon sets are included for iOS and watchOS. Their editable SVG sources are in `Resources/IconSources`.

Enable these capabilities for the Watch target:

- HealthKit;
- Background Modes → Workout processing.
- App Groups → `group.com.gergokondor.RouteLatchApp.watchkitapp` for both the Watch app and `RouteLatch Workout Widget` extension.

The checked-in Watch entitlements declare HealthKit. The Watch Info.plist includes:

- `NSHealthShareUsageDescription` for live heart rate;
- `NSHealthUpdateUsageDescription` for the workout and actual route;
- `NSLocationWhenInUseUsageDescription` for guidance;
- `WKBackgroundModes` with `workout-processing`.

WatchConnectivity needs matching signing teams and the companion bundle relationship; it does not require immediate reachability. The phone uses `transferFile`, and the Watch immediately decodes/copies the temporary received file into its own store. Duplicate receipt is idempotent because route IDs map to stable filenames. After persistence, the Watch queues a background receipt acknowledgement so the phone distinguishes “transferred” from “available on Apple Watch.”

## Strava integration

Completed runs are encoded as timestamped TCX files from the actual GPS samples and active workout duration. The Watch keeps each run in a pending store until the iPhone acknowledges receipt. The iPhone keeps a local TCX copy, uploads it directly to Strava with the `activity:write` permission, persists asynchronous upload IDs for safe retries, and records the resulting Strava activity ID to prevent duplicate submissions. Every run can also be shared manually as TCX.

OAuth access and refresh tokens are stored in the iOS Keychain. The Strava client secret is never compiled into the app: `Backend/api/strava-token.mjs` performs only authorization-code exchange, token refresh, and revocation. Workout files never pass through the backend.

The production Strava connection is configured as follows:

1. The Strava API application uses callback domain `routelatch.app`.
2. The token broker is deployed at `https://route-latch.vercel.app/api/strava-token`.
3. The iOS target contains the public Strava Client ID and production broker URL in its build settings.
4. `STRAVA_CLIENT_ID` and the encrypted `STRAVA_CLIENT_SECRET` are configured for the Vercel Production environment.
5. Install the iPhone/Watch build, open the Strava screen on iPhone, and tap **Connect with Strava**.

If a development build omits these deployment values, Health saving, Watch-to-iPhone run retention, TCX creation, and manual TCX sharing continue to work, while the Strava screen reports that automatic upload is not configured.

## Build and test

Open `RouteLatch.xcodeproj` in Xcode 26.6 or newer. The deployment targets are iOS 17 and watchOS 10 because the UI uses modern SwiftUI Map content such as `MapPolyline`.

Command-line checks used for this repository:

```sh
swift test --package-path Packages/RouteLatchCore
xcodebuild -project RouteLatch.xcodeproj -target 'RouteLatch Watch App' -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RouteLatch.xcodeproj -target RouteLatch -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

The local Xcode installation includes iOS 17.5/26.5 and watchOS 26.5 simulator runtimes. The iPhone 17 Pro and Apple Watch Series 11 simulator builds were installed and launched successfully, and their seeded route-library screens were visually checked. Simulators are useful for import, persistence, maps, layout, and state UI, but HealthKit workout sessions, real WatchConnectivity delivery, haptics, live heart rate, background location behavior, GPS quality, and workout-route saving ultimately require a physical paired iPhone and Apple Watch.

## Run on a paired iPhone and Apple Watch

1. Confirm that Xcode is signed in to the Apple Developer account that owns team `595EKYS652`; both targets already use that team and the RouteLatch bundle IDs.
2. Confirm HealthKit and workout-processing capabilities on the Watch target.
3. Select the paired iPhone/Watch run destination in Xcode and install the iPhone scheme.
4. Launch both apps once so WatchConnectivity activates.
5. Import a `.gpx` with the iPhone file picker or open/share one into RouteLatch.
6. Open the route, tap **Send to Apple Watch**, and allow background delivery time.
7. Optionally enable **Target pace alerts**, set the min/km slider, and send the updated route. The goal can also be adjusted on the Watch route screen.
8. On Watch, tap **Free Run** or open a local route and tap **Start Guidance**. Accept Health and Location prompts.
9. Optionally add **RouteLatch Live Run** to the Watch Smart Stack for live pace and workout controls.

## Manual outdoor QA

- Import track, route-only, namespaced, multi-segment, malformed, duplicate, and large GPX samples.
- Confirm route framing, start/finish markers, distance/ascent, rename, persistence, deletion, and Dynamic Type in light/dark mode.
- Queue a route while the Watch app is inactive; later verify offline receipt and selection with the phone out of range.
- Start, pause, resume, and finish both a guided run and a Free Run; confirm elapsed time, actual distance, average pace, and heart rate are plausible.
- Stop a guided run before the GPX finish and confirm average pace remains `active time / actual distance`; no unvisited course distance may affect it.
- Add the rectangular Smart Stack widget and verify live time, distance, average pace, pause/resume, and finish while the Watch app is not visible.
- Set a target pace on iPhone, transfer it, and confirm the same value and planned duration on Watch. Change it locally on Watch and confirm it persists after relaunch.
- Set, persist, disable, and re-enable a Free Run target pace; confirm the live target/schedule display and the same warm-up, behind-goal, recovery, haptic, and cooldown behavior as a guided run.
- Run behind the target after the 500 m/3-minute warm-up, recover into the 5% band, and verify yellow status, schedule delta, projected duration, warning/recovery haptics, and cooldown.
- Move beyond 40 m, hover between 25–40 m, and return below 25 m; verify alert, cooldown, hysteresis, and visible non-color status.
- Confirm the saved Health workout contains only locations actually visited.
- Connect Strava, finish a run with the iPhone temporarily offline, then reconnect; verify the Watch transfer, queued retry, one Strava activity, matching timestamps/distance, and manual TCX share fallback.
- Test loops, out-and-backs, starting midway, start-near-finish courses, poor GPS, stationary drift, and disconnected segments.
- Measure battery behavior on a representative long run.

## Known MVP limitations

- This is route-line guidance, not turn-by-turn navigation; generic GPX files do not contain dependable turn instructions.
- Base-map tiles may need network access. Stored geometry, matching, progress, metrics, and warnings remain offline.
- Transfer progress is intentionally coarse: queued, transferred, and Watch-persisted acknowledgement. WatchConnectivity does not provide byte-level remote progress.
- The original imported GPX is retained for provenance; normalized routes are separately stored on phone and Watch.
- Pace goals are whole-run targets rather than adaptive training plans and do not account for grade, terrain, aid stations, or split-specific pacing.
- Physical-device behavior, permission prompts, background execution, haptic feel, and actual HealthKit route saving cannot be fully automated on this machine.
- Automatic Strava upload requires a registered Strava API application and a deployed token broker; these production credentials are intentionally not committed.
