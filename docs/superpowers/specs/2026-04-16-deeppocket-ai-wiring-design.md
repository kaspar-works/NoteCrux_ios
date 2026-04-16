# DeepPocket.ios — AI Wiring & Orphan Service Integration

**Date:** 2026-04-16
**Status:** Approved pending implementation and user review

## 1. Goal

Make every advertised feature of DeepPocket.ios actually work end-to-end. Two parts:

- **Verify the existing local heuristic pipeline** runs cleanly from recording → insights → display, fixing any bugs found.
- **Replace the empty Foundation Models stubs** in `LocalInsightGenerator` and `MeetingAssistantEngine` with real on-device LLM calls, with automatic fallback to heuristics on devices without Apple Intelligence.
- **Wire the three orphaned services** — `CalendarIntegrationService`, `DeepPocketShortcuts`, `MeetingExportService` — into reachable UI surfaces.

## 2. Scope

**In scope**
- Foundation Models integration for `LocalInsightGenerator` (summary, action items, decisions, risks, highlights).
- Foundation Models integration for `MeetingAssistantEngine` (Q&A in the Search tab).
- Calendar import: Dashboard "Today's agenda" section showing today's events, with an "Upcoming" sub-list for the next 7 days; tap any event to start a recording pre-tagged with it.
- Siri shortcuts: Start Recording, Today's Agenda, Ask DeepPocket, Last Meeting Decisions.
- Per-meeting share sheet (markdown notes + audio file).
- Bulk export from Settings (zip of markdown files only — see §8).
- End-to-end manual smoke test of the full pipeline (heuristic + FM paths).

**Out of scope**
- Speaker diarization upgrades (`SpeakerLabeler` stays heuristic).
- `ProInsightsEngine` analytics changes.
- Any cloud / network-based AI (Claude API, OpenAI, etc.).
- Building an XCTest target — the project has zero tests today; adding test infrastructure is a separate initiative.
- Calendar export-back (writing recorded meetings back to the user's calendar).
- A "regenerate insights" button.
- Telemetry / analytics.

## 3. Architecture

### 3.1 Foundation Models integration pattern

Fill in the existing `#if canImport(FoundationModels)` stub at `LocalInsightGenerator.swift:240-244`. Same pattern applied to `MeetingAssistantEngine`. The public API of both services stays unchanged — every existing call site works without modification. The heuristic path becomes the automatic fallback when FM is unavailable at runtime.

A single `FoundationModelClient` wraps `LanguageModelSession`, exposes:
- `isAvailable: Bool` (checks `SystemLanguageModel.default.availability`)
- `generateInsights(from transcript: String) async throws -> InsightDraft`
- `answer(question: String, context: [MeetingContext]) async throws -> String`
- Internal: transcript chunking helper for context-budget-aware processing.

Structured output uses `@Generable` types so the LLM returns parsed `InsightDraft` directly rather than text-parsed JSON.

### 3.2 Long transcript handling (map-reduce)

Apple's on-device model has a limited context window. As a conservative planning assumption we treat usable context as roughly ~4K tokens, and a 30-minute meeting transcript as roughly ~6K tokens. Real numbers vary by model version, locale, and content.

Strategy:

- If transcript fits comfortably in a single call → one FM call returning structured `InsightDraft`.
- If longer → split into roughly equal chunks under the planning budget → summarize each chunk → final FM call merges chunk summaries and dedupes action items → return `InsightDraft`.

Action items are extracted per chunk and deduped in the merge step: titles are normalized (lowercased, trimmed, punctuation stripped) and compared for equality first, with a fuzzy-match fallback (e.g., Levenshtein distance ≤ 3 or token-set ratio ≥ 0.85) before collapsing duplicates. Chunk-size constants and the dedupe threshold live in `FoundationModelClient` and can be tuned without spec changes.

### 3.3 Hardware fallback

iOS deployment target is 18.2, which is the minimum for Foundation Models, but Apple Intelligence requires iPhone 15 Pro+ or M-series iPad/Mac. On unsupported devices, `SystemLanguageModel.default.availability` returns unavailable; the existing heuristic path runs unchanged. No user-visible error, no feature toggle UI, no degraded "Apple Intelligence required" screen.

### 3.4 Concurrency, cancellation, and session caching

- **Single active generation per meeting.** `LocalInsightGenerator` tracks the current in-flight `Task` per meeting ID; a second `generate(from:)` call for the same meeting is a no-op (returns the existing task's result). Concurrent calls for *different* meetings are allowed.
- **Cancellation-aware FM path.** All FM work runs inside `Task` handles owned by the calling view (`RecordingRoomView`, `AssistantView`). On view disappear or meeting delete, the task is cancelled; `FoundationModelClient` checks `Task.isCancelled` between chunks and propagates `CancellationError` cleanly.
- **In-memory session cache.** `FoundationModelClient` keeps a small LRU cache (transcript hash → `InsightDraft`) for the current app session only, capped at ~10–20 entries to bound memory. Avoids re-running FM if a user reopens the same meeting within a session. Cache is purged on app background; nothing persists to disk beyond the existing `Meeting` fields.

### 3.5 Orphan service wiring

| Orphan | Wired into | Notes |
|---|---|---|
| `CalendarIntegrationService` → renamed `CalendarImportService` | `DashboardView` "Today's agenda" + "Upcoming" rows | Read-oriented integration using the current EventKit permission flow available on supported iOS versions |
| `DeepPocketShortcuts` | Registered in `DeepPocket_iosApp.init()`; backed by 4 new `AppIntent` types | Surfaces in Spotlight, Siri, Shortcuts app |
| `MeetingExportService` | Per-meeting share button in `InsightView` + bulk export button in `SettingsView` | Adds `shareItems(for:)` returning markdown + audio URL |

## 4. Components & file changes

### 4.1 New files

- `DeepPocket.ios/Services/FoundationModelClient.swift` — single shared `LanguageModelSession` wrapper, availability check, chunking helper, `@Generable` structured-output types, error handling.
- `DeepPocket.ios/Services/CalendarImportService.swift` — wraps `EKEventStore`, exposes `upcomingEvents() async -> [CalendarEventSummary]`. Replaces `CalendarIntegrationService.swift`.
- `DeepPocket.ios/Intents/DeepPocketIntents.swift` — `StartRecordingIntent`, `TodaysAgendaIntent`, `AskDeepPocketIntent`, `LastMeetingDecisionsIntent`. Existing `DeepPocketShortcuts` `AppShortcutsProvider` declaration updated to register them.
- `DeepPocket.ios/Views/MeetingShareSheet.swift` — `UIViewControllerRepresentable` wrapping `UIActivityViewController`.

### 4.2 Modified files

- `DeepPocket.ios/Services/LocalInsightGenerator.swift` — replace stub body at `:241-244` with real `FoundationModelClient.generateInsights(from:)` call inside a do/catch that falls back to `generateHeuristicInsights` on any throw.
- `DeepPocket.ios/Services/MeetingAssistantEngine.swift` — add FM-backed answer path; existing keyword-search becomes the fallback when FM is unavailable or throws.
- `DeepPocket.ios/DeepPocket_iosApp.swift` — call `DeepPocketShortcuts.updateAppShortcutParameters()` in `init`.
- `DeepPocket.ios/Views/DashboardView.swift` — "Today's agenda" section driven by `CalendarImportService`; tap-to-record-with-event-context.
- `DeepPocket.ios/Views/SettingsView.swift` — "Calendar access" toggle + "Export all meetings" button.
- `DeepPocket.ios/Views/InsightView.swift` (or current per-meeting detail view) — share button presenting `MeetingShareSheet`.
- `DeepPocket.ios/Services/MeetingExportService.swift` — add public `shareItems(for: Meeting) -> [Any]` returning markdown + audio file URL.
- `Info.plist` — add the calendar usage description key(s) required by the EventKit permission flow chosen at implementation time.

### 4.3 Files renamed / removed

- `CalendarIntegrationService.swift` → `CalendarImportService.swift` (zero existing call sites; safe rename).

## 5. Data flow

### 5.1 Recording → AI insights

```
RecordingRoomView (stop)
  → LocalInsightGenerator.generate(from:)
    → SystemLanguageModel.default.availability
      ├─ Available + transcript fits planning budget → FoundationModelClient.generateInsights() → InsightDraft
      ├─ Available + transcript exceeds budget → chunk → summarize each → merge → InsightDraft
      └─ Unavailable / FM throws → generateHeuristicInsights() → InsightDraft
  → Meeting persisted via modelContext (no schema change)
```

### 5.2 Assistant Q&A

```
AssistantView (user query)
  → MeetingAssistantEngine.answer(query:)
    → keyword score → top-N relevant Meetings
    → if FM available: FoundationModelClient.answer(question, context: summaries)
        → composed answer rendered with cited meeting titles + tap-through to each
        → cap citations at top 3–5 to avoid UI clutter
    → if FM unavailable: render the keyword result list under the header
        "Showing related meetings", with a one-line snippet per match and tap to open
```

Note: assistant context is meeting **summaries**, not full transcripts, to stay within the FM context budget. Quality of summaries is now FM-grade, so this is acceptable.

### 5.3 Calendar agenda

```
DashboardView.onAppear
  → CalendarImportService.upcomingEvents()
    → first call triggers calendar permission prompt
    → granted → render "Today's agenda" (today's events) + "Upcoming" sub-list (next 7 days)
    → denied → render a small collapsed card "Calendar access is off" with an "Enable" action
               that deep-links to the app's iOS Settings page (iOS blocks repeated prompts
               after first denial, so re-requesting in-app is not viable)
    → fetch fails → render a lightweight "Calendar unavailable" state and log
  → tap event → RecordingRoomView pre-filled with event title + attendees as tags
```

### 5.4 Siri shortcuts

- `StartRecordingIntent` — foreground, opens app, navigates to Dashboard, starts recording. Implemented via app launch handoff into a shared navigation/recording coordinator (a small `AppRouter` observable owned by `DeepPocket_iosApp` that intents post a "start recording" request to and that `ContentView` / `DashboardView` react to).
- `TodaysAgendaIntent` — background, returns a spoken `IntentResult` summarizing today's scheduled calendar events (e.g., "You have 3 meetings today: …"). Pulls from `CalendarImportService`.
- `AskDeepPocketIntent(question:)` — background, runs through `MeetingAssistantEngine`, speaks the answer. Answer length is capped to a short spoken-friendly response (~2–4 sentences) to avoid rambling Siri output; longer detail stays in-app.
- `LastMeetingDecisionsIntent` — background, reads the `decisions` array of the most recent `Meeting`.

### 5.5 Export

- Per-meeting share → `MeetingShareSheet` with `[markdown notes, audio file URL]`.
- Bulk export → `MeetingExportService.exportAll()` → zip of markdown files in temp dir → share sheet. Files are named `<sanitized-meeting-title>__<ISO-date>.md` (e.g., `Weekly-planning__2026-04-16.md`) for sortable, readable archives. Audio files are **not** included in v1 bulk export (see §8).

## 6. Error handling

| Failure | Behavior |
|---|---|
| FM unavailable at startup | Heuristic path used; no user message |
| FM throws mid-generation | Caught; fall back to heuristic; logged via `os_log` |
| FM returns malformed structured output | Caught; fall back to heuristic |
| Calendar permission denied | Show small "Calendar access is off" card with an Enable action |
| Calendar fetch fails | Show lightweight "Calendar unavailable" state; logged |
| Siri intent throws | iOS surfaces a generic error to the user |
| Per-meeting share — payload creation fails before presenting the share sheet | In-app error alert |
| Bulk export fails | Error alert in `SettingsView` (user-initiated) |

**Principle:** AI features fail silently with graceful degradation. User-initiated transactional actions (share, export) surface errors visibly.

**Logging boundary:** all FM-path failures, chunk counts, fallback events, and cancellation events are logged at `debug` level via `os_log` under a single subsystem (e.g., `works.kaspar.deeppocket`, category `ai`). No PII (no transcript content) is logged — only counts, durations, error types. This is for internal diagnosis, not telemetry.

## 7. Testing & verification

No automated test target exists currently. Verification is a manual end-to-end smoke test on both iOS Simulator (heuristic path, no Apple Intelligence) and a physical Apple Intelligence-capable device (FM path). Verification checklist:

1. **Heuristic path (Simulator)** — record a 2-min sample with explicit phrases ("decided to ship Friday", "Alice will follow up", "blocker: API timeout", "by next Tuesday"). Confirm Dashboard / Tasks / Highlights / Search render summary, action items (with owner + deadline + priority), decisions, risks. Fix issues found during smoke testing as part of this initiative.
2. **FM path (physical device)** — same recording. Confirm output is qualitatively better (full sentences, deduped action items, accurate owners). With Wi-Fi/cellular off, confirm everything still works (true on-device).
3. **Long transcript** — paste a ~20-min sample transcript via debug entry; confirm chunked map-reduce returns coherent output.
4. **Calendar** — grant + deny permission paths both render correctly; events appear; tap-to-record carries event context.
5. **Each Siri shortcut** — invoke from Shortcuts app; confirm spoken output and app navigation for all four.
6. **Per-meeting share** — share to Files, Mail, Notes; confirm markdown formatting + audio attachment.
7. **Bulk export** — Settings button → zip downloaded → unzip → check markdown formatting and per-meeting separation.

If a step cannot be tested (e.g., no Apple Intelligence device available), this is reported explicitly in the result rather than claimed as success.

## 8. Non-obvious decisions

- **No persistent FM-output cache beyond the existing `Meeting` fields.** Re-running insights on an existing meeting would overwrite. No "regenerate" button in v1. An in-memory session cache (see §3.4) avoids redundant FM calls within a single app session.
- **`CalendarImportService` uses the current EventKit permission flow available on supported iOS versions.** The permission scope chosen is the minimum that lets the dashboard read upcoming events; exact API surface is decided at implementation time.
- **Renaming `CalendarIntegrationService` → `CalendarImportService`** is safe — file has zero existing call sites.
- **`AskDeepPocketIntent` answers from meeting summaries, not full transcripts.** Required for FM context budget. Quality depends on stored summaries (now FM-grade).
- **Heuristic path is the contract.** The FM path must produce output of the same shape (`InsightDraft`) and the same persistence model (`Meeting`). No schema changes.
- **No analytics, no telemetry added.** Matches current app posture (everything stays on-device).
- **Bulk export is markdown-only in v1.** Audio files remain available through the per-meeting share path. This keeps the bulk-export payload small and predictable; a "full archive (notes + audio)" option can be added later if users ask for it.

## 9. Future considerations (not v1)

- **Insight confidence score.** Surface whether a `Meeting`'s insights came from the FM path or the heuristic fallback, plus an internal quality score. Helps debugging, builds user trust, and gives a UX hook for "regenerate with AI" once that feature exists. Deliberately deferred — would require a schema field on `Meeting` and a UI affordance to display it.

## 10. Risks

- **FM behavior may differ between iOS minor versions.** Mitigation: catch all errors and fall back; pin no specific FM behavior.
- **Apple Intelligence rollout still uneven across regions/devices.** Most users may run the heuristic path. The heuristics must remain robust — verification step 1 is non-negotiable.
- **Long transcript map-reduce can lose nuance.** Acceptable trade for any kind of FM output on long recordings vs. failing entirely.
- **EventKit permission UX is intrusive.** Mitigation: only request when Dashboard agenda row is first viewed, not at app launch.
