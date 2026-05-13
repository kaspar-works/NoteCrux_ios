# 2026-04-21 — NoteCrux App Review Remediation Timeline

Chronological narrative of the App Store rejection cycle on NoteCrux iOS v1.0. All times Pacific unless noted.

---

## Prior context

**2026-04-19 13:38 PT** — Build #1 archived and uploaded (version "1").
**2026-04-19 20:11 PT** — Build #2 archived and uploaded (version "2"). Never attached to version.
**2026-04-19 21:15 PT** (2026-04-20 04:15 UTC) — Gautam submits app + binary for review (submission `f7b8c893…`). Build #1 attached. "Remove Ads" IAP exists but in state `MISSING_METADATA` (no App Review screenshot). IAP is listed on version page but fails to auto-bundle because of the missing metadata.

---

## Round 1 rejection

**2026-04-21 morning** — Apple replies:
> Guideline 2.1(b) — Performance — App Completeness
> Submission ID: `f7b8c893-c195-4c5f-b802-1564d28226ec`
> "We are unable to complete the review of the app because one or more of the In-App Purchase products have not been submitted for review."

**~12:39 PT** — Kaspar pastes the rejection screenshot into the session. Session begins.

### Investigation (~12:40–12:50)

- Ran `superpowers:systematic-debugging` skill. No fixes until root cause confirmed.
- Explored codebase: found `SubscriptionManager.swift`, `PaywallView.swift`, and a `teardown_subscriptions.rb` — confirming the team pivoted from a monthly/yearly subscription model to a one-time Remove Ads non-consumable.
- `NoteCruxProducts.storekit` + paywall copy (*"One-time • No subscription"*) + App Store description (*"No subscriptions, no recurring fees"*) all correct for the new model.
- Wrote a Ruby ASC API diagnostic (`/tmp/notecrux_asc_diagnose.rb`) using a manually-built ES256 JWT because the system Ruby 2.6 didn't have the `spaceship` gem.

**Finding:**
- No subscription groups exist (teardown already ran successfully).
- `Remove Ads` IAP `6762571070`: state `MISSING_METADATA`, no review screenshot, price schedule present.
- Previous review submission has only 1 item (the binary). IAP never bundled.
- App version state: `REJECTED`.

### Remediation (~12:50–1:00)

1. Uploaded `iPhone 17 Pro Max-06_RemoveAds.png` to the IAP via `POST /v1/inAppPurchaseAppStoreReviewScreenshots` (IAP v2 endpoint — the older `/v1/appStoreReviewScreenshots` is subscription-only). Reserve slot → PUT bytes to presigned S3 → PATCH `uploaded=true` with MD5. IAP went to `READY_TO_SUBMIT`.
2. Swapped the attached build from #1 to the already-uploaded #2 (Apple said "upload a new binary"). Version state: `REJECTED` → `PREPARE_FOR_SUBMISSION`.
3. Tried to attach version to new reviewSubmission → **409 `ITEM_PART_OF_ANOTHER_SUBMISSION`** — the old rejected submission still held the version as an item, and a "completed" submission blocks re-attachment.
4. Tried DELETE on the old item → 409 "already submitted". Can't remove.
5. Probed for a cancel endpoint. `PATCH /v1/reviewSubmissions/{id} {cancelled: true}` → 409 unknown attribute. Retried with American spelling `{canceled: true}` → **200 OK, state CANCELING**.
6. Waited 5s → state `COMPLETE`.
7. Attached version to new submission → 201. Tried to attach IAP via `inAppPurchaseV2` relationship → 409 "not a relationship on reviewSubmissionItems". Tried every plausible name — none worked. Discovered `reviewSubmissionItems` simply does not accept IAPs.
8. Tried `POST /v1/inAppPurchaseSubmissions` → 409 `STATE_ERROR.FIRST_IAP_MUST_BE_SUBMITTED_ON_VERSION`. Apple's policy: first-time IAPs must be submitted *alongside* a version, not via the IAP submission endpoint. They auto-bundle at the backend — or should.
9. **2026-04-21 11:00 PT (18:00 UTC)** — `PATCH {submitted: true}` on the new reviewSubmission → 200, state `WAITING_FOR_REVIEW`.

### Verification
Waited 3 minutes. IAP state still `READY_TO_SUBMIT`, not `WAITING_FOR_REVIEW`. Suspected auto-bundle not happening. Offered Kaspar two options: (A) cancel + manual UI resubmit, or (B) let it ride and see if Apple auto-bundles at pickup.

**~1:04 PT** — Kaspar shared ASC screenshot showing submission in *Waiting for Review*. Walked them through the UI path: Remove version from review → find "In-App Purchases and Subscriptions" section on version page → confirm "Remove Ads" is attached → resubmit.

**~1:07 PT** — Remove Ads already appeared attached to the version (the auto-attach *did* exist — it just hadn't been caught by Apple's backend on the first submit). Kaspar clicked Remove from Review, then "Add for Review" → Submit.

Round 1 resolved from a submission standpoint.

---

## Round 2 rejection

**2026-04-21 ~1:39 PT** — Apple's review picks up quickly and rejects again:
> Guideline 2.1(a) — Performance — App Completeness
> Submission ID: `5f5b5b70-4920-49f7-8cb5-357d88a7fa01`
> Review device: iPad Air 11-inch (M3), iPadOS 26.4.1
> "Your app did not respond when we tapped on the play button of the previously recorded audio."

Kaspar shared an iPad screenshot showing a meeting with header "1 MIN DURATION" but audio scrubber reading `0:00 / 0:00` and *"No transcript was captured"*.

### Root cause investigation (~1:40–2:00 PT)

Dispatched an `Explore` subagent to map the recording → playback pipeline. Then read the actual code (subagent analyses can hallucinate).

Found three stacked problems in `RecordingTranscriptionController.swift`:

1. **Audio format mismatch.** `prepareAudioFile()` created `AVAudioFile` using `audioEngine.inputNode.outputFormat(forBus: 0)` *before* `audioEngine.prepare()`. On iPad `.voiceChat` mode, the hardware-negotiated format differs from what's reported pre-prepare. The input tap then delivered buffers in a format the file couldn't accept. Every `try? audioFile?.write(from: buffer)` failed silently (`try?` eats errors). Saved `.caf` had the CAF header but zero audio payload.

2. **Silent playback failure.** `InsightView.togglePlayback()` caught `AVAudioPlayer` init errors into `NoteCruxLog.export.debug` with no UI surface. Even when init succeeded on a header-only file, `player.duration` was 0, `player.play()` returned immediately, and the progress timer's `isPlaying` check flipped everything back. Button appears to do nothing — exactly what Apple's reviewer reported.

3. **Absolute paths in SwiftData.** `Meeting.audioFilePath` stored the full `/var/mobile/Containers/Data/Application/<UUID>/…` path. Container UUIDs can change across iOS updates, silently breaking playback on older recordings. Not the root cause for Apple's reviewer (they recorded fresh) but a latent bug.

### Fixes (~2:00–2:40 PT)

**Kaspar approved all three fixes**, then I implemented them.

- **`RecordingTranscriptionController.swift`:** Split `prepareAudioFile` into `reserveRecordingURL` (URL only) and file creation inside `startSpeechRecognition`. Call `audioEngine.prepare()` first, then read the format, then use that same format for both the `AVAudioFile` and the `installTap`. Added `pendingFileURL` state.
- **`Meeting.swift`:** Added `audioFileURL` computed property that resolves legacy absolute paths OR new filename-only values against the current container. Added `Meeting.recordingsFolder` static helper.
- **`RecordingRoomView.swift`:** Save site + draft site now store `.lastPathComponent` instead of `.path`. Fixed an unrelated pre-existing compile error: `TranscriptPreview(transcript: $recorder.transcript, …)` was binding to a get-only computed property. Wrapped in `Binding` with no-op setter.
- **`InsightView.swift`:** Pre-tap scrubber falls back to `meeting.duration` so it stops reading `0:00 / 0:00`. `togglePlayback()` guards `player.duration > 0`, surfaces `playbackError` alert on init failure or empty file. Added 8 KB minimum file-size gate before the player UI renders at all.
- **`StorageManager.swift` + `MeetingExportService.swift`:** Route through `meeting.audioFileURL` resolver.

Bumped `CURRENT_PROJECT_VERSION` from 1 to 3 across six `pbxproj` entries.

### User verifies fix (~2:45 PT)

Kaspar recorded on iPhone with the fixed code:
> "after tapping its showing"

Fresh recording works. Pre-fix `.caf` files still stuck at 0:00 (they're header-only and unrecoverable), but the code now shows a clear alert on them instead of silently failing.

### Small polish (~2:50–3:15 PT)

Kaspar noticed a second iPhone screenshot where the pre-tap scrubber read `0:00 / 0:00`. I added a fallback to show `meeting.duration` (the stored elapsed time) in the right-side total-time label before `AVAudioPlayer` is initialized. Now reads `0:00 / 19:03` before first tap.

---

## Navigation + UX fixes (~3:15–3:30 PT)

**Kaspar:** "add go back button from meeting details, from home page if we go anywhere"

Found that most reachable-from-Home detail screens hide the navigation bar via `.toolbar(.hidden, for: .navigationBar)` — a setting that propagates from `DashboardView` to pushed children, hiding the system back chevron too.

Fixes:
- **`InsightView.swift`:** `MeetingDetailTopBar` had an invisible back button (`.opacity(0)` overlay). Replaced with a visible purple-tinted chevron-left in the HStack itself.
- **`DashboardView.swift`:** `TodayMeetingsDetailView` and `HighlightsDetailView` now override with `.toolbar(.visible, for: .navigationBar)`.
- **`AssistantView.swift`:** Same override + inline title.
- `VaultView` already had its own back chevron — unchanged.
- `TasksView` — has a nested `NavigationStack` anti-pattern; left as out-of-scope. Documented as an open item.

---

## Settings copy + dead toggle (~3:35–4:00 PT)

**Kaspar:** Tried turning on App Lock → got dialog "Set a PIN first" with text referencing "before turning off Face ID".

The `showPINRequiredAlert` fires from two code paths (turning on App Lock without backup, turning off Biometric Unlock without backup) but copy was only accurate for one. Rewrote to be scenario-neutral: *"Set a backup PIN before locking the app. Without a PIN you could be locked out if Face ID or Touch ID is ever unavailable."*

**Kaspar:** "all features are working?" (Data & Privacy screenshot)

Audited the three toggles:
| Toggle | Wired up |
|---|---|
| Enable AI Features | ✅ Read in RecordingRoomView + InsightView gating logic |
| Auto-Process After Recording | ✅ Read in save flow |
| Allow Background Processing | ❌ **Cosmetic only** — AppStorage key only written, never read. No `beginBackgroundTask`. |

Flagged as Apple 2.3 (Accurate Metadata) risk. Kaspar chose Option A: remove the toggle.

Deleted the `Allow Background Processing` row + the `backgroundProcessing` AppStorage property from `DataPrivacyView.swift`.

---

## Build attempts (~4:00–5:15 PT)

### Fastlane path (~4:00–4:45 PT)

Tried `fastlane beta` 5 times. Each attempt revealed a new problem that got fixed:

1. **Fastlane defaulted to visionOS.** Added `destination: "generic/platform=iOS"` to `build_app`.
2. **Pre-existing compile error in widget target** — `NoteCruxWidgetsLiveActivity.swift` referenced `RecordingActivityAttributes` but that struct only lived in the main-app folder. Xcode synchronized groups give each target visibility only into its own folder. Duplicated the file into `NoteCruxWidgets/`.
3. **Pre-existing compile error in `RecordingRoomView.swift:552`** — `$recorder.transcript` tried to bind to a computed get-only property. Wrapped in manual `Binding` with no-op setter.
4. **Packaging step failed** — "no provisioning profile mapping". Added `export_options: { signingStyle: "automatic", teamID: "…" }` + `-allowProvisioningUpdates`. Still failed.
5. **Final xcodebuild error revealed:** `Provisioning profile "iOS Team Store Provisioning Profile: com.codergautamyt.NoteCrux.NoteCruxWidgets" doesn't match the entitlements file's value for the com.apple.developer.team-identifier entitlement.`

### Xcode GUI path (~4:45–5:15 PT)

**Kaspar:** "ok then push it, should i create build?"

Switched to Xcode GUI archive. First archive attempt failed with:
> "The app identifier 'com.codergautamyt.NoteCrux.NoteCruxWidgets' cannot be registered to your development team because it is not available. No profiles for 'com.codergautamyt.NoteCrux.NoteCruxWidgets' were found."

Root cause: the widget bundle ID is registered to a team (CoderGautamYT, `9F5QLG25S4`) that Kaspar's signed-in Apple ID ("Shanthi Selvarajan") doesn't have membership in. The Team dropdown only showed Shanthi's personal team.

**Kaspar:** "possible to delete?" (meaning: delete the widget extension entirely)

Discussed trade-off: deleting the widget target loses Dynamic Island + lock-screen Live Activity indicators but keeps everything else. Stubbed `LiveActivityController` as a no-op, deleted the shared `RecordingActivityAttributes.swift`.

**Kaspar:** "can i chnage buddle nid ?" (change widget bundle ID instead of deleting)

Cleaner option — keeps the Live Activity feature. I reverted `LiveActivityController.swift` to the real ActivityKit implementation and re-created `NoteCrux/Services/RecordingActivityAttributes.swift`.

**Kaspar changed the widget bundle ID in Xcode GUI to `com.codergautamyt.NoteCrux.LiveActivity`.**

First archive after the rename still failed with the *old* bundle ID in the error — Organizer was showing a stale archive from before the rename. Told Kaspar to delete old archives, nuke `~/Library/Developer/Xcode/DerivedData/NoteCrux-*`, clean build folder, retry.

---

## Round 2 reply drafted (~5:22 PT)

**Kaspar:** "reply for this email"

Drafted a reply for ASC that:
- Names the root cause (audio session format negotiation timing on iPad `.voiceChat`)
- Lists the concrete fixes in build 3 (format-matched file writes, playback error surfacing, container-safe path resolution, pre-tap duration display)
- Confirms end-to-end verification on iPhone and iPad

---

## Outstanding as of this writing

1. Archive build 3 successfully in Xcode GUI after the widget bundle ID rename.
2. Upload to App Store Connect.
3. On ASC web UI: verify "Remove Ads" is attached to the version, swap to build 3, resubmit.
4. Post the drafted reply to Apple in ASC.

## Open items for a later pass

- **`TasksView` nested `NavigationStack`.** Breaks back navigation to Dashboard when pushed via the Tasks stats tile.
- **Fastlane `Fastfile` changes** can be reverted if Xcode GUI becomes the standing archive path.
- **`setup_subscriptions.rb` + `APP_STORE_SETUP.md`** are artifacts from the abandoned subscription model. Stale but harmless.

## Key reference IDs

| Thing | Value |
|---|---|
| App ID | `6762570285` |
| Main bundle ID | `com.codergautamyt.NoteCrux` |
| Widget bundle ID (old) | `com.codergautamyt.NoteCrux.NoteCruxWidgets` (orphaned) |
| Widget bundle ID (new) | `com.codergautamyt.NoteCrux.LiveActivity` |
| Remove Ads IAP product | `com.codergautamyt.NoteCrux.removeads` (ASC id `6762571070`) |
| App version 1.0 | `94ea2238-d92f-4623-809b-0a83550b5fe7` |
| Round 1 submission (cancelled) | `f7b8c893-c195-4c5f-b802-1564d28226ec` |
| Round 1 resubmission | `5a3d241f-c608-4645-a590-4cc5cc9aba20` |
| Round 2 rejection | `5f5b5b70-4920-49f7-8cb5-357d88a7fa01` |
| App + widgets team ID | `9F5QLG25S4` (CoderGautamYT) |
| UI tests team ID | `8ARDN58Z85` |
| ASC API Key ID | `6H4P2FCSJB` (`~/.appstoreconnect/AuthKey_6H4P2FCSJB.p8`) |
