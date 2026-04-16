# NoteCrux AI Wiring & Orphan Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the three orphan services (Calendar import, Siri Shortcuts, Export) into reachable UI surfaces and replace the empty Foundation Models stubs with real on-device LLM calls that fall back to existing heuristics on unsupported devices. Verify the heuristic pipeline end-to-end.

**Architecture:** Fill in the existing `#if canImport(FoundationModels)` stub at `LocalInsightGenerator.swift:240-244` with a shared `FoundationModelClient` wrapping `LanguageModelSession` and `@Generable` structured outputs. Replace the export-back-only `CalendarIntegrationService` with a new import-only `CalendarImportService`. Introduce a small `AppRouter` observable so Siri intents can hand off to in-app navigation. All AI failures fall back silently to heuristics.

**Tech Stack:** SwiftUI, SwiftData, `FoundationModels` (iOS 18.2+), `EventKit`, `AppIntents`, `os_log`.

**Adaptations to plan defaults:**
- **No TDD / no XCTest.** The approved spec excludes building a test target. Each task ends with manual verification (Simulator or device smoke test) instead of automated assertions.
- **No `git commit` steps.** Project is not a git repo. Each task ends with a "checkpoint — Xcode builds clean" step. `git init` can be added later without affecting the plan.

**Working tree:** `/Users/bistrokaspar/projects/Kasparworks/NoteCrux`
**Source root:** `NoteCrux/` (relative to the working tree)
**Plan source:** `docs/superpowers/specs/2026-04-16-deeppocket-ai-wiring-design.md`

---

## File structure

**New files (5):**
- `NoteCrux/Services/FoundationModelClient.swift` — on-device LLM wrapper (availability, structured output, chunking, cache, cancellation, logging).
- `NoteCrux/Services/CalendarImportService.swift` — `EKEventStore` wrapper for import-only agenda.
- `NoteCrux/Intents/DeepPocketIntents.swift` — four `AppIntent` types.
- `NoteCrux/Views/MeetingShareSheet.swift` — `UIActivityViewController` wrapper.
- `NoteCrux/AppRouter.swift` — `@Observable` coordinator for intent → app navigation.

**Modified files (~9):**
- `NoteCrux/Services/LocalInsightGenerator.swift` — fill in FM stub, add concurrency guard.
- `NoteCrux/Services/MeetingAssistantEngine.swift` — add FM-backed async `answer(...)`.
- `NoteCrux/Services/MeetingExportService.swift` — add `shareItems(for:)` and `exportAll()`.
- `NoteCrux/Services/NoteCruxShortcuts.swift` — register four intents.
- `NoteCrux/NoteCruxApp.swift` — own `AppRouter`, inject via `.environment`, call `updateAppShortcutParameters`.
- `NoteCrux/ContentView.swift` — react to `AppRouter` requests; pass event-context to `RecordingRoomView`.
- `NoteCrux/Views/DashboardView.swift` — Today's agenda + Upcoming + denied-state card.
- `NoteCrux/Views/SettingsView.swift` — "Export all meetings" button.
- `NoteCrux/Views/InsightView.swift` — per-meeting share button.
- `NoteCrux/Views/RecordingRoomView.swift` — optional `initialContext` init param for calendar tap-to-record.

**Deleted files (1):**
- `NoteCrux/Services/CalendarIntegrationService.swift` — export-back is out of scope; `CalendarImportService` replaces it with a different API shape.

**Info.plist:** `NSCalendarsFullAccessUsageDescription` is **already present** (via `INFOPLIST_KEY_*` in `project.pbxproj`). No Info.plist edits required.

---

## Task ordering (dependencies)

```
Task 1 (Heuristic smoke test) ─────────────────────────────────┐
Task 2 (AppRouter + logging)                                    │
Task 3 (FoundationModelClient: skeleton)                        │
Task 4 (FoundationModelClient: chunking + cache + cancellation) │
Task 5 (LocalInsightGenerator: FM path) ← 3, 4                  │
Task 6 (MeetingAssistantEngine: FM path) ← 3, 4                 │
Task 7 (CalendarImportService)                                  │
Task 8 (RecordingRoomView: initialContext param)                │
Task 9 (DashboardView: agenda + denied card) ← 7, 8             │
Task 10 (MeetingExportService: shareItems + exportAll)          │
Task 11 (MeetingShareSheet view) ← 10                           │
Task 12 (InsightView: share button) ← 11                        │
Task 13 (SettingsView: export-all button) ← 10                  │
Task 14 (DeepPocketIntents) ← 2, 6, 7                           │
Task 15 (NoteCruxShortcuts + App entry wiring) ← 2, 14        │
Task 16 (End-to-end smoke test) ← everything                    │
```

---

## Task 1: Verify heuristic pipeline on Simulator (baseline)

**Purpose:** Before adding AI, confirm the existing heuristic path works end-to-end. Any bugs found here get fixed inline; they are not "AI bugs" they are "my feature doesn't work" bugs.

**Files:** None modified in this task except possible inline heuristic fixes.

- [ ] **Step 1: Build & launch on iOS Simulator (iPhone 15, non-Pro — no Apple Intelligence).**

  Run in Xcode: `⌘R` with target scheme `NoteCrux`, destination `iPhone 15 Simulator (iOS 18.2)`.

  Expected: app launches, lands on `DashboardView`.

- [ ] **Step 2: Record a 90-second sample meeting.**

  Tap the record button in the Dashboard → `RecordingRoomView` opens. Read aloud (or use Simulator → Features → "Speak Selected Text"):

  > "Good morning. Alice will follow up with the vendor by next Tuesday. We decided to ship Friday. The blocker is an API timeout. This is urgent; we must fix it before the launch. Bob, please prepare the migration plan."

  Tap stop/save. Confirm the loading UI completes and the sheet dismisses.

- [ ] **Step 3: Verify Dashboard populates.**

  Back on Dashboard, confirm:
  - "Recent meetings" section shows the new meeting.
  - Tap the meeting → `InsightView` opens → summary is non-empty, bullet summary has items.

  If any section is blank, open the service file and trace why. Fix inline. Typical fixes: nil-handling in `LocalInsightGenerator.generate(...)`, off-by-one in `cleanTaskTitle`, or empty-transcript edge case.

- [ ] **Step 4: Verify Tasks tab.**

  Open Tasks tab. Confirm at least one action item is extracted from the sample — expected: "Alice will follow up with the vendor by next Tuesday" (detected via "will ", "follow up", deadline "next Tuesday" → next Tuesday 09:00).

- [ ] **Step 5: Verify Highlights tab.**

  Open Highlights (ProInsights). Expect at least a rendered view; cross-meeting analytics are sparse with one recording and may be near-empty, which is acceptable. What's NOT acceptable: a crash or blank screen with no state message.

- [ ] **Step 6: Verify Search (Assistant) tab.**

  Type "shipping" → expect the meeting to appear in results. Type nonsense ("qwxzf") → expect an empty result UI, not a crash.

- [ ] **Step 7: Capture baseline notes.**

  Create a scratchpad file at `docs/superpowers/plans/notes/2026-04-16-baseline.md` with:
  - Simulator device + iOS version.
  - What worked.
  - Any bugs found and fixed inline (file:line + short description).

  This is the "heuristic path verified" gate for the spec's §7 verification step 1.

- [ ] **Step 8: Checkpoint.**

  In Xcode run Product → Clean Build Folder (⇧⌘K), then Build (⌘B).
  Expected: Build Succeeded, zero warnings.

---

## Task 2: AppRouter + logging subsystem

**Purpose:** A single observable coordinator that Siri intents post to, and that `ContentView` reacts to. Also sets up the `os_log` subsystem used by FM paths and calendar.

**Files:**
- Create: `NoteCrux/AppRouter.swift`
- Create: `NoteCrux/NoteCruxLog.swift`

- [ ] **Step 1: Create `NoteCruxLog.swift`.**

  Create `NoteCrux/NoteCruxLog.swift`:

  ```swift
  import Foundation
  import OSLog

  enum NoteCruxLog {
      static let subsystem = "works.kaspar.notecrux"

      static let ai = Logger(subsystem: subsystem, category: "ai")
      static let calendar = Logger(subsystem: subsystem, category: "calendar")
      static let intents = Logger(subsystem: subsystem, category: "intents")
      static let export = Logger(subsystem: subsystem, category: "export")
  }
  ```

- [ ] **Step 2: Create `AppRouter.swift`.**

  Create `NoteCrux/AppRouter.swift`:

  ```swift
  import Foundation
  import Observation

  /// Shared coordinator for intent → app navigation.
  /// Siri intents post requests here; ContentView observes and reacts.
  @Observable
  final class AppRouter {
      /// Set by intents to request that the app open the recording sheet.
      /// ContentView clears this after consuming.
      var pendingRecordingRequest: RecordingRequest?

      struct RecordingRequest: Identifiable, Equatable {
          let id = UUID()
          let title: String?
          let tags: [String]

          static let blank = RecordingRequest(title: nil, tags: [])
      }

      func requestRecording(title: String? = nil, tags: [String] = []) {
          pendingRecordingRequest = RecordingRequest(title: title, tags: tags)
          NoteCruxLog.intents.debug("AppRouter: recording requested, title=\(title ?? "-", privacy: .public)")
      }

      func consumeRecordingRequest() -> RecordingRequest? {
          let request = pendingRecordingRequest
          pendingRecordingRequest = nil
          return request
      }
  }
  ```

- [ ] **Step 3: Verify it compiles.**

  In Xcode: ⌘B.
  Expected: Build Succeeded. `AppRouter` and `NoteCruxLog` are not used yet — that's fine.

- [ ] **Step 4: Checkpoint.**

  Xcode shows zero warnings for the two new files.

---

## Task 3: FoundationModelClient — skeleton & single-shot path

**Purpose:** A single shared wrapper around `LanguageModelSession`. This task gets availability + single-call insight generation working. Chunking, cache, and cancellation come in Task 4.

**Files:**
- Create: `NoteCrux/Services/FoundationModelClient.swift`

- [ ] **Step 1: Create the file with `@Generable` output types.**

  Create `NoteCrux/Services/FoundationModelClient.swift`:

  ```swift
  import Foundation
  import OSLog

  #if canImport(FoundationModels)
  import FoundationModels

  @Generable
  struct FMInsightOutput {
      @Guide(description: "Three to five sentence summary of the meeting in plain prose.")
      var summary: String

      @Guide(description: "A short, single-paragraph note suitable for a daily digest.")
      var paragraphNotes: String

      @Guide(description: "Bullet list of the main points, 3 to 7 items, each one short line.")
      var bulletSummary: [String]

      @Guide(description: "The most quotable or interesting lines from the meeting, up to 5.")
      var highlights: [String]

      @Guide(description: "Concrete decisions that were made. Empty list if none.")
      var decisions: [String]

      @Guide(description: "Risks, blockers, or concerns raised. Empty list if none.")
      var risks: [String]

      @Guide(description: "Discrete action items extracted from the meeting.")
      var actionItems: [FMActionItemOutput]
  }

  @Generable
  struct FMActionItemOutput {
      @Guide(description: "Short imperative title, under 80 characters.")
      var title: String

      @Guide(description: "One-sentence detail explaining the task.")
      var detail: String

      @Guide(description: "Owner name if stated or implied, else 'Unassigned'.")
      var owner: String

      @Guide(description: "Natural-language deadline if mentioned, else empty string.")
      var deadline: String

      @Guide(description: "Priority: 'high', 'medium', or 'low'.")
      var priority: String
  }

  @Generable
  struct FMAnswerOutput {
      @Guide(description: "Direct answer to the user's question in 2 to 4 sentences, spoken-friendly.")
      var answer: String

      @Guide(description: "Up to 5 meeting titles cited as sources for the answer.")
      var citedMeetingTitles: [String]
  }
  #endif
  ```

- [ ] **Step 2: Add the client type and availability check.**

  Append to `FoundationModelClient.swift`:

  ```swift
  /// Shared on-device LLM client. Returns heuristic-shaped output on success,
  /// and throws on any failure so callers can fall back to heuristics.
  final class FoundationModelClient {
      static let shared = FoundationModelClient()

      enum ClientError: Error {
          case unavailable
          case generationFailed(underlying: Error)
          case cancelled
      }

      var isAvailable: Bool {
          #if canImport(FoundationModels)
          switch SystemLanguageModel.default.availability {
          case .available: return true
          case .unavailable: return false
          @unknown default: return false
          }
          #else
          return false
          #endif
      }

      private init() {}
  }
  ```

- [ ] **Step 3: Add a single-shot insight generation method.**

  Append to `FoundationModelClient` (inside the class):

  ```swift
      func generateInsights(from transcript: String) async throws -> FMInsightOutput {
          #if canImport(FoundationModels)
          guard isAvailable else {
              NoteCruxLog.ai.debug("FM unavailable; caller should use heuristic fallback.")
              throw ClientError.unavailable
          }

          let session = LanguageModelSession()
          let prompt = Self.insightPrompt(transcript: transcript)

          do {
              let start = Date()
              let response = try await session.respond(to: prompt, generating: FMInsightOutput.self)
              let duration = Date().timeIntervalSince(start)
              NoteCruxLog.ai.debug("FM insight generation ok, duration=\(duration, format: .fixed(precision: 2))s")
              return response.content
          } catch is CancellationError {
              NoteCruxLog.ai.debug("FM insight generation cancelled.")
              throw ClientError.cancelled
          } catch {
              NoteCruxLog.ai.debug("FM insight generation failed: \(String(describing: error), privacy: .public)")
              throw ClientError.generationFailed(underlying: error)
          }
          #else
          throw ClientError.unavailable
          #endif
      }

      private static func insightPrompt(transcript: String) -> String {
          """
          You are an assistant that extracts structured notes from a meeting transcript.
          Read the transcript below and return a populated FMInsightOutput value.

          Rules:
          - Be faithful to the transcript. Do not invent facts, names, or dates.
          - If a field has no content in the transcript, use an empty string or empty list.
          - Keep summaries short and direct.

          Transcript:
          \(transcript)
          """
      }
  ```

- [ ] **Step 4: Add the assistant answer method.**

  Append:

  ```swift
      struct MeetingContext {
          let title: String
          let summary: String
          let createdAt: Date
      }

      func answer(question: String, context: [MeetingContext]) async throws -> FMAnswerOutput {
          #if canImport(FoundationModels)
          guard isAvailable else { throw ClientError.unavailable }

          let session = LanguageModelSession()
          let prompt = Self.answerPrompt(question: question, context: context)

          do {
              let response = try await session.respond(to: prompt, generating: FMAnswerOutput.self)
              NoteCruxLog.ai.debug("FM answer ok, cites=\(response.content.citedMeetingTitles.count)")
              return response.content
          } catch is CancellationError {
              throw ClientError.cancelled
          } catch {
              NoteCruxLog.ai.debug("FM answer failed: \(String(describing: error), privacy: .public)")
              throw ClientError.generationFailed(underlying: error)
          }
          #else
          throw ClientError.unavailable
          #endif
      }

      private static func answerPrompt(question: String, context: [MeetingContext]) -> String {
          let formatter = ISO8601DateFormatter()
          formatter.formatOptions = [.withFullDate]
          let bullets = context.map { item in
              "- [\(item.title) — \(formatter.string(from: item.createdAt))] \(item.summary)"
          }.joined(separator: "\n")

          return """
          You are DeepPocket, a concise meeting assistant.
          Answer the user's question using ONLY the meeting notes below.
          If the notes do not contain the answer, say so briefly.
          Keep the answer to 2 to 4 sentences, suitable for being spoken aloud.
          Cite up to 5 meeting titles you used.

          Meeting notes:
          \(bullets)

          Question: \(question)
          """
      }
  ```

- [ ] **Step 5: Build.**

  Xcode: ⌘B.
  Expected: Build Succeeded. If `FoundationModels` module is unknown, confirm iOS deployment target is 18.2 (already set) and that the scheme's target device is Apple Intelligence-capable; the `#if canImport` block guards it on Simulator.

- [ ] **Step 6: Checkpoint.**

  Zero warnings. No call sites yet — they come in Tasks 5 and 6.

---

## Task 4: FoundationModelClient — chunking, cache, cancellation

**Purpose:** Add long-transcript map-reduce, the in-memory LRU session cache, and cancellation-awareness.

**Files:**
- Modify: `NoteCrux/Services/FoundationModelClient.swift`

- [ ] **Step 1: Add the cache.**

  Insert this nested type inside `FoundationModelClient` (above `private init`):

  ```swift
      private struct SessionCache {
          private var order: [String] = []
          private var store: [String: FMInsightOutput] = [:]
          private let limit = 20

          mutating func get(_ key: String) -> FMInsightOutput? {
              guard let value = store[key] else { return nil }
              if let idx = order.firstIndex(of: key) {
                  order.remove(at: idx)
                  order.append(key)
              }
              return value
          }

          mutating func put(_ key: String, _ value: FMInsightOutput) {
              if store[key] != nil {
                  order.removeAll { $0 == key }
              } else if store.count >= limit, let evict = order.first {
                  order.removeFirst()
                  store.removeValue(forKey: evict)
              }
              store[key] = value
              order.append(key)
          }

          mutating func purge() {
              order.removeAll()
              store.removeAll()
          }
      }

      private var cache = SessionCache()
      private let cacheQueue = DispatchQueue(label: "works.kaspar.notecrux.fm.cache")
  ```

- [ ] **Step 2: Add a cache-key helper and wrap `generateInsights`.**

  Rename the current `generateInsights(from:)` body to `generateInsightsUncached(from:)` (still private-ish, keep internal access). Then re-add a public `generateInsights(from:)` that consults the cache:

  Replace the existing `generateInsights` method with:

  ```swift
      func generateInsights(from transcript: String) async throws -> FMInsightOutput {
          try Task.checkCancellation()
          let key = Self.cacheKey(for: transcript)

          if let hit = cacheQueue.sync(execute: { cache.get(key) }) {
              NoteCruxLog.ai.debug("FM cache hit")
              return hit
          }

          let output = try await generateInsightsUncached(from: transcript)
          cacheQueue.sync { cache.put(key, output) }
          return output
      }

      private func generateInsightsUncached(from transcript: String) async throws -> FMInsightOutput {
          try Task.checkCancellation()
          #if canImport(FoundationModels)
          guard isAvailable else { throw ClientError.unavailable }

          let chunks = Self.chunk(transcript: transcript)
          NoteCruxLog.ai.debug("FM generation, chunks=\(chunks.count)")

          if chunks.count == 1 {
              return try await singleShotInsight(chunks[0])
          }

          // Map: summarize each chunk
          var chunkSummaries: [String] = []
          chunkSummaries.reserveCapacity(chunks.count)
          for (i, chunk) in chunks.enumerated() {
              try Task.checkCancellation()
              let partial = try await singleShotInsight(chunk)
              chunkSummaries.append("Chunk \(i + 1): \(partial.summary)\nBullets: \(partial.bulletSummary.joined(separator: " | "))")
          }

          // Reduce: final call merges the chunk summaries
          let merged = chunkSummaries.joined(separator: "\n\n")
          let final = try await singleShotInsight(merged)

          // Action items across chunks need their own merge pass
          var actionItemsAllChunks: [FMActionItemOutput] = []
          for chunk in chunks {
              try Task.checkCancellation()
              let out = try await singleShotInsight(chunk)
              actionItemsAllChunks.append(contentsOf: out.actionItems)
          }

          let deduped = Self.dedupeActionItems(actionItemsAllChunks)

          return FMInsightOutput(
              summary: final.summary,
              paragraphNotes: final.paragraphNotes,
              bulletSummary: final.bulletSummary,
              highlights: final.highlights,
              decisions: final.decisions,
              risks: final.risks,
              actionItems: deduped
          )
          #else
          throw ClientError.unavailable
          #endif
      }
  ```

- [ ] **Step 3: Extract the single-shot call.**

  Append to the class:

  ```swift
      #if canImport(FoundationModels)
      private func singleShotInsight(_ transcript: String) async throws -> FMInsightOutput {
          try Task.checkCancellation()
          let session = LanguageModelSession()
          let prompt = Self.insightPrompt(transcript: transcript)
          do {
              let response = try await session.respond(to: prompt, generating: FMInsightOutput.self)
              return response.content
          } catch is CancellationError {
              throw ClientError.cancelled
          } catch {
              throw ClientError.generationFailed(underlying: error)
          }
      }
      #endif
  ```

- [ ] **Step 4: Add chunking + cache key + dedupe helpers.**

  Append:

  ```swift
      /// Planning assumption: ~4 characters per token; conservative single-call budget ≈ 2,500 tokens → 10,000 characters.
      private static let singleCallCharacterBudget = 10_000
      private static let chunkCharacterSize = 8_000

      static func chunk(transcript: String) -> [String] {
          let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
          guard clean.count > singleCallCharacterBudget else { return [clean] }

          let sentences = clean
              .components(separatedBy: CharacterSet(charactersIn: ".?!\n"))
              .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
              .filter { !$0.isEmpty }

          var chunks: [String] = []
          var current = ""
          for sentence in sentences {
              if current.count + sentence.count + 2 > chunkCharacterSize, !current.isEmpty {
                  chunks.append(current)
                  current = ""
              }
              current += sentence + ". "
          }
          if !current.isEmpty { chunks.append(current) }
          return chunks
      }

      static func cacheKey(for transcript: String) -> String {
          let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
          return "\(normalized.count):\(normalized.hashValue)"
      }

      static func dedupeActionItems(_ items: [FMActionItemOutput]) -> [FMActionItemOutput] {
          var seenNormalized: [String] = []
          var out: [FMActionItemOutput] = []

          for item in items {
              let norm = normalizedTitle(item.title)
              if seenNormalized.contains(where: { isDuplicate($0, norm) }) { continue }
              seenNormalized.append(norm)
              out.append(item)
          }
          return out
      }

      private static func normalizedTitle(_ title: String) -> String {
          let lowered = title.lowercased()
          let allowed = CharacterSet.alphanumerics.union(.whitespaces)
          let filtered = lowered.unicodeScalars.filter { allowed.contains($0) }
          return String(String.UnicodeScalarView(filtered))
              .trimmingCharacters(in: .whitespaces)
              .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      }

      private static func isDuplicate(_ a: String, _ b: String) -> Bool {
          if a == b { return true }
          let setA = Set(a.split(separator: " "))
          let setB = Set(b.split(separator: " "))
          let inter = setA.intersection(setB).count
          let union = setA.union(setB).count
          guard union > 0 else { return false }
          return Double(inter) / Double(union) >= 0.85
      }
  ```

- [ ] **Step 5: Purge cache on app background.**

  Add a public method that `NoteCruxApp` will call in Task 15:

  ```swift
      func purgeSessionCache() {
          cacheQueue.sync { cache.purge() }
          NoteCruxLog.ai.debug("FM session cache purged")
      }
  ```

- [ ] **Step 6: Build.**

  ⌘B. Expected: Build Succeeded.

- [ ] **Step 7: Checkpoint.**

  Confirm zero warnings. `FoundationModelClient` is still unused by callers.

---

## Task 5: LocalInsightGenerator — wire in the FM path

**Purpose:** Replace the empty FM stub at `LocalInsightGenerator.swift:241-244` with real calls to `FoundationModelClient.shared`, mapping `FMInsightOutput` → `InsightDraft`. Heuristic path stays untouched as the fallback.

**Files:**
- Modify: `NoteCrux/Services/LocalInsightGenerator.swift`

- [ ] **Step 1: Replace the stub body.**

  In `LocalInsightGenerator.swift`, find the existing block:

  ```swift
      #if canImport(FoundationModels)
      private func generateWithFoundationModels(from transcript: String) async -> InsightDraft {
          generateHeuristicInsights(from: transcript)
      }
      #endif
  ```

  Replace it with:

  ```swift
      #if canImport(FoundationModels)
      private func generateWithFoundationModels(from transcript: String) async -> InsightDraft {
          let client = FoundationModelClient.shared
          do {
              let fm = try await client.generateInsights(from: transcript)
              return convert(fm: fm, transcript: transcript)
          } catch FoundationModelClient.ClientError.cancelled {
              NoteCruxLog.ai.debug("LocalInsightGenerator: cancelled, returning heuristic fallback")
              return generateHeuristicInsights(from: transcript)
          } catch {
              NoteCruxLog.ai.debug("LocalInsightGenerator: FM failed, using heuristic fallback")
              return generateHeuristicInsights(from: transcript)
          }
      }

      private func convert(fm: FMInsightOutput, transcript: String) -> InsightDraft {
          let sentences = transcript
              .components(separatedBy: CharacterSet(charactersIn: ".?!\n"))
              .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
              .filter { !$0.isEmpty }
          let rankedSentences = sentences.sorted { score($0) > score($1) }
          let importantLines = Array(rankedSentences.filter { score($0) >= 3 }.prefix(8))
          let quickRead = Array(rankedSentences.prefix(3)).joined(separator: ". ")

          let actionItems = fm.actionItems.map { item in
              ActionItemDraft(
                  title: item.title,
                  detail: item.detail,
                  owner: item.owner.isEmpty ? "Unassigned" : item.owner,
                  deadline: parseDeadline(item.deadline),
                  priority: parsePriority(item.priority),
                  confidence: .high,
                  sourceQuote: item.detail
              )
          }

          return InsightDraft(
              summary: fm.summary,
              paragraphNotes: fm.paragraphNotes,
              bulletSummary: fm.bulletSummary,
              highlights: fm.highlights,
              importantLines: importantLines,
              quickRead: quickRead.isEmpty ? fm.summary : quickRead + ".",
              keyPoints: fm.bulletSummary,
              decisions: fm.decisions,
              risks: fm.risks,
              actionItems: actionItems
          )
      }

      private func parseDeadline(_ text: String) -> Date? {
          guard !text.isEmpty else { return nil }
          return detectDueDate(in: text)
      }

      private func parsePriority(_ text: String) -> TaskPriority {
          switch text.lowercased() {
          case "high", "urgent", "critical": return .high
          case "low", "nice to have": return .low
          default: return .medium
          }
      }
      #endif
  ```

  Note: `detectDueDate(in:)` already exists on `LocalInsightGenerator` at line 162; reusing it keeps date handling consistent between paths.

- [ ] **Step 2: Add concurrency guard.**

  At the top of `LocalInsightGenerator` (before `func generate(from:) async -> InsightDraft`), change the `struct` to something that can hold state. Replace:

  ```swift
  struct LocalInsightGenerator {
  ```

  with:

  ```swift
  final class LocalInsightGenerator {
      private var inflight: [String: Task<InsightDraft, Never>] = [:]
      private let inflightQueue = DispatchQueue(label: "works.kaspar.notecrux.insight.inflight")
  ```

  Then wrap `generate(from:)` to dedupe:

  ```swift
      func generate(from transcript: String) async -> InsightDraft {
          let key = "\(transcript.count):\(transcript.hashValue)"

          if let existing = inflightQueue.sync(execute: { inflight[key] }) {
              return await existing.value
          }

          let task = Task<InsightDraft, Never> { [weak self] in
              guard let self else {
                  return InsightDraft(
                      summary: "Generator unavailable.",
                      paragraphNotes: "",
                      bulletSummary: [],
                      highlights: [],
                      importantLines: [],
                      quickRead: "",
                      keyPoints: [],
                      decisions: [],
                      risks: [],
                      actionItems: []
                  )
              }
              let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
              guard !clean.isEmpty else {
                  return InsightDraft(
                      summary: "No transcript was captured.",
                      paragraphNotes: "No transcript was captured, so DeepPocket could not generate notes.",
                      bulletSummary: [],
                      highlights: [],
                      importantLines: [],
                      quickRead: "No transcript captured.",
                      keyPoints: [],
                      decisions: [],
                      risks: [],
                      actionItems: []
                  )
              }

              #if canImport(FoundationModels)
              return await self.generateWithFoundationModels(from: clean)
              #else
              return self.generateHeuristicInsights(from: clean)
              #endif
          }

          inflightQueue.sync { inflight[key] = task }
          let result = await task.value
          inflightQueue.sync { inflight[key] = nil }
          return result
      }
  ```

  Delete the original `func generate(from transcript: String) async -> InsightDraft { ... }` body above, because it's now replaced.

- [ ] **Step 3: Update call sites that instantiate `LocalInsightGenerator`.**

  Search the project for `LocalInsightGenerator()`. Based on the earlier audit, call sites are:
  - `RecordingRoomView.swift:23`
  - `DashboardView.swift:12`

  Both are likely `let generator = LocalInsightGenerator()`. With the change from `struct` to `final class`, these still work — no call-site edits needed. Confirm by building.

- [ ] **Step 4: Build.**

  ⌘B. Expected: Build Succeeded.

- [ ] **Step 5: Simulator smoke test (still heuristic path).**

  Run on iPhone 15 Simulator. Repeat the 90-second recording from Task 1.
  Expected: summary and action items still populate; heuristic fallback is fully functional because FM is unavailable on this simulator.

- [ ] **Step 6: Checkpoint.**

  Zero warnings; Simulator smoke test still green.

---

## Task 6: MeetingAssistantEngine — FM-backed answer path

**Purpose:** The Search/Assistant tab currently does keyword matching. Add an async FM path that composes a natural-language answer; fall back to the existing synchronous method on failure.

**Files:**
- Modify: `NoteCrux/Services/MeetingAssistantEngine.swift`
- Modify: `NoteCrux/Views/AssistantView.swift` (call site update)

- [ ] **Step 1: Rename the existing sync method.**

  In `MeetingAssistantEngine.swift`, find:

  ```swift
  func answer(question: String, meetings: [Meeting], tasks: [MeetingActionItem]) -> String {
  ```

  Rename to `keywordAnswer(...)`:

  ```swift
  func keywordAnswer(question: String, meetings: [Meeting], tasks: [MeetingActionItem]) -> String {
  ```

- [ ] **Step 2: Add a new async wrapper that prefers FM.**

  Add at the top of the struct (below existing properties):

  ```swift
      struct AnswerResult {
          let answer: String
          let citedMeetings: [Meeting]
          let usedFM: Bool
      }

      func answer(
          question: String,
          meetings: [Meeting],
          tasks: [MeetingActionItem],
          topN: Int = 5
      ) async -> AnswerResult {
          let ranked = rankedMeetings(for: question, in: meetings).prefix(topN)
          let context = ranked.map { meeting in
              FoundationModelClient.MeetingContext(
                  title: meeting.title,
                  summary: meeting.summary,
                  createdAt: meeting.createdAt
              )
          }

          guard FoundationModelClient.shared.isAvailable else {
              return AnswerResult(
                  answer: keywordAnswer(question: question, meetings: meetings, tasks: tasks),
                  citedMeetings: Array(ranked),
                  usedFM: false
              )
          }

          do {
              let fm = try await FoundationModelClient.shared.answer(question: question, context: context)
              // Map cited titles back to Meetings; capped at 5 in the prompt.
              let cited = fm.citedMeetingTitles.compactMap { title in
                  meetings.first(where: { $0.title == title })
              }
              return AnswerResult(answer: fm.answer, citedMeetings: cited, usedFM: true)
          } catch {
              NoteCruxLog.ai.debug("MeetingAssistantEngine: FM failed, falling back to keyword")
              return AnswerResult(
                  answer: keywordAnswer(question: question, meetings: meetings, tasks: tasks),
                  citedMeetings: Array(ranked),
                  usedFM: false
              )
          }
      }

      /// Simple keyword-score ranking for context selection. Independent of keywordAnswer output text.
      func rankedMeetings(for query: String, in meetings: [Meeting]) -> [Meeting] {
          let terms = query
              .lowercased()
              .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
              .map(String.init)
              .filter { $0.count >= 3 }

          guard !terms.isEmpty else { return meetings.sorted { $0.createdAt > $1.createdAt } }

          func score(_ meeting: Meeting) -> Int {
              let haystack = (meeting.title + " " + meeting.summary + " " + meeting.transcript).lowercased()
              return terms.reduce(0) { partial, term in
                  partial + (haystack.contains(term) ? 1 : 0)
              }
          }

          return meetings
              .map { (score($0), $0) }
              .filter { $0.0 > 0 }
              .sorted { $0.0 > $1.0 }
              .map { $0.1 }
      }
  ```

- [ ] **Step 3: Update `AssistantView` to call the async path.**

  Open `NoteCrux/Views/AssistantView.swift`. Find where `engine.answer(...)` is called and update the call site to `async/await`. If `AssistantView` has a submit handler like:

  ```swift
  private func submit() {
      let result = engine.answer(question: query, meetings: meetings, tasks: tasks)
      messages.append(.init(id: UUID(), role: .assistant, text: result, createdAt: Date()))
  }
  ```

  Replace with:

  ```swift
  @State private var isAnswering = false
  @State private var lastCitations: [Meeting] = []

  private func submit() {
      Task {
          isAnswering = true
          defer { isAnswering = false }
          let result = await engine.answer(question: query, meetings: meetings, tasks: tasks)
          lastCitations = result.citedMeetings
          messages.append(.init(id: UUID(), role: .assistant, text: result.answer, createdAt: Date()))
      }
  }
  ```

  If `AssistantView` uses different state names, adapt: the pattern is `Task { await engine.answer(...) }` and store citations + answer text.

- [ ] **Step 4: Add citations row under the assistant message.**

  In the message-rendering view section of `AssistantView`, below the assistant text, add:

  ```swift
  if !lastCitations.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
          Text("Sources")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          ForEach(lastCitations.prefix(5)) { meeting in
              NavigationLink(destination: InsightView(meeting: meeting)) {
                  HStack {
                      Image(systemName: "doc.text")
                      Text(meeting.title)
                          .font(.caption)
                      Spacer()
                  }
              }
              .buttonStyle(.plain)
          }
      }
      .padding(.top, 8)
  }
  ```

- [ ] **Step 5: Build.**

  ⌘B. Expected: Build Succeeded.

- [ ] **Step 6: Simulator smoke test.**

  Run the Assistant tab, type a question like "what did we ship".
  Expected on Simulator (no FM): keyword answer + up to 5 sources from keyword-ranked meetings.

- [ ] **Step 7: Checkpoint.**

  Zero warnings; smoke test passes.

---

## Task 7: CalendarImportService (replaces CalendarIntegrationService)

**Purpose:** Delete the export-back-only `CalendarIntegrationService` (out of scope) and create a new import-only service that feeds the Dashboard agenda.

**Files:**
- Delete: `NoteCrux/Services/CalendarIntegrationService.swift`
- Create: `NoteCrux/Services/CalendarImportService.swift`

- [ ] **Step 1: Delete the old file.**

  In Xcode project navigator, right-click `CalendarIntegrationService.swift` → Delete → "Move to Trash". (The file has zero call sites per the earlier audit, so this is safe.)

- [ ] **Step 2: Create `CalendarImportService.swift`.**

  Create `NoteCrux/Services/CalendarImportService.swift`:

  ```swift
  import Foundation
  import EventKit

  struct CalendarEventSummary: Identifiable, Hashable {
      let id: String              // EKEvent.eventIdentifier
      let title: String
      let startDate: Date
      let endDate: Date
      let attendees: [String]     // display names
      let isToday: Bool
  }

  enum CalendarAuthorizationState {
      case notDetermined
      case granted
      case denied
  }

  @MainActor
  final class CalendarImportService: ObservableObject {
      static let shared = CalendarImportService()

      @Published private(set) var authorizationState: CalendarAuthorizationState = .notDetermined
      @Published private(set) var events: [CalendarEventSummary] = []

      private let store = EKEventStore()
      private let calendar = Calendar.current

      private init() {
          self.authorizationState = Self.currentState()
      }

      func requestAccessIfNeeded() async {
          switch EKEventStore.authorizationStatus(for: .event) {
          case .authorized, .fullAccess:
              authorizationState = .granted
          case .denied, .restricted:
              authorizationState = .denied
          case .notDetermined:
              do {
                  let granted = try await store.requestFullAccessToEvents()
                  authorizationState = granted ? .granted : .denied
              } catch {
                  NoteCruxLog.calendar.debug("EventStore access request failed: \(String(describing: error), privacy: .public)")
                  authorizationState = .denied
              }
          case .writeOnly:
              authorizationState = .denied
          @unknown default:
              authorizationState = .denied
          }
      }

      /// Returns today's events + upcoming events for the next 7 days, sorted by start date.
      func refresh() async {
          await requestAccessIfNeeded()
          guard authorizationState == .granted else {
              events = []
              return
          }

          let now = Date()
          guard let windowEnd = calendar.date(byAdding: .day, value: 7, to: now) else {
              events = []
              return
          }

          let predicate = store.predicateForEvents(
              withStart: calendar.startOfDay(for: now),
              end: windowEnd,
              calendars: nil
          )
          let raw = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

          events = raw.map { event in
              CalendarEventSummary(
                  id: event.eventIdentifier,
                  title: event.title ?? "Untitled event",
                  startDate: event.startDate,
                  endDate: event.endDate,
                  attendees: (event.attendees ?? []).compactMap { $0.name },
                  isToday: calendar.isDateInToday(event.startDate)
              )
          }

          NoteCruxLog.calendar.debug("CalendarImport: loaded \(self.events.count) events")
      }

      var todaysEvents: [CalendarEventSummary] {
          events.filter { $0.isToday }
      }

      var upcomingEvents: [CalendarEventSummary] {
          events.filter { !$0.isToday }
      }

      private static func currentState() -> CalendarAuthorizationState {
          switch EKEventStore.authorizationStatus(for: .event) {
          case .authorized, .fullAccess: return .granted
          case .denied, .restricted, .writeOnly: return .denied
          case .notDetermined: return .notDetermined
          @unknown default: return .notDetermined
          }
      }
  }
  ```

- [ ] **Step 3: Build.**

  ⌘B. Expected: Build Succeeded. `EKEvent.attendees` is optional; the nil-coalesce is deliberate.

- [ ] **Step 4: Checkpoint.**

  Zero warnings. Service is unused until Task 9.

---

## Task 8: RecordingRoomView — optional initial context

**Purpose:** Let the Dashboard's "Today's agenda" tap open a recording pre-filled with event title + attendees as tags.

**Files:**
- Modify: `NoteCrux/Views/RecordingRoomView.swift`

- [ ] **Step 1: Add the init parameter.**

  At the top of `RecordingRoomView`, add this struct and state variable near the existing `@State private var meetingTitle: String`:

  ```swift
      struct InitialContext: Equatable {
          let title: String
          let tags: [String]
      }

      let initialContext: InitialContext?

      init(initialContext: InitialContext? = nil) {
          self.initialContext = initialContext
      }
  ```

- [ ] **Step 2: Apply context on appear.**

  In the existing `.task { ... }` modifier (around line 141), add at the top:

  ```swift
  if let ctx = initialContext {
      if meetingTitle.isEmpty { meetingTitle = ctx.title }
      for tag in ctx.tags where !selectedTags.contains(tag) {
          selectedTags.append(tag)
      }
  }
  ```

- [ ] **Step 3: Build.**

  ⌘B. Existing `.sheet { RecordingRoomView() }` call in `ContentView.swift` still works because `initialContext` defaults to nil.

- [ ] **Step 4: Checkpoint.**

  Zero warnings.

---

## Task 9: DashboardView — agenda sections + denied state

**Purpose:** Show today's calendar events ("Today's agenda") + a smaller "Upcoming" list; tap to start a recording with event context; render a small "Calendar access is off" card if denied.

**Files:**
- Modify: `NoteCrux/Views/DashboardView.swift`
- Modify: `NoteCrux/ContentView.swift` (to carry `initialContext` through the sheet)

- [ ] **Step 1: Add shared state for the pending record request.**

  In `ContentView.swift`, change:

  ```swift
  @State private var isRecording = false
  ```

  to:

  ```swift
  @State private var isRecording = false
  @State private var recordingInitialContext: RecordingRoomView.InitialContext? = nil
  ```

  And update the `.sheet`:

  ```swift
  .sheet(isPresented: $isRecording, onDismiss: { recordingInitialContext = nil }) {
      RecordingRoomView(initialContext: recordingInitialContext)
  }
  ```

  Pass the binding down to `DashboardView`. Find where `DashboardView(isRecording: $isRecording)` is instantiated and extend to:

  ```swift
  DashboardView(
      isRecording: $isRecording,
      recordingInitialContext: $recordingInitialContext
  )
  ```

- [ ] **Step 2: Add the new binding to `DashboardView`.**

  In `DashboardView.swift`, add near the existing `@Binding var isRecording: Bool`:

  ```swift
  @Binding var recordingInitialContext: RecordingRoomView.InitialContext?
  @StateObject private var calendarService = CalendarImportService.shared
  ```

- [ ] **Step 3: Refresh calendar on appear.**

  In the body's outermost `.task { ... }` or `.onAppear { ... }`, add:

  ```swift
  .task {
      await calendarService.refresh()
  }
  ```

  If there's already a `.task`, add `await calendarService.refresh()` inside it.

- [ ] **Step 4: Add the agenda section view.**

  Add this helper view method inside `DashboardView`:

  ```swift
  @ViewBuilder
  private var agendaSection: some View {
      switch calendarService.authorizationState {
      case .granted:
          if calendarService.events.isEmpty {
              EmptyView()
          } else {
              VStack(alignment: .leading, spacing: 12) {
                  Text("Today's agenda")
                      .font(.headline)
                  if calendarService.todaysEvents.isEmpty {
                      Text("No events today.")
                          .font(.subheadline)
                          .foregroundStyle(.secondary)
                  } else {
                      ForEach(calendarService.todaysEvents) { event in
                          agendaRow(event: event)
                      }
                  }
                  if !calendarService.upcomingEvents.isEmpty {
                      Divider().padding(.top, 4)
                      Text("Upcoming")
                          .font(.subheadline.weight(.semibold))
                          .foregroundStyle(.secondary)
                      ForEach(calendarService.upcomingEvents.prefix(5)) { event in
                          agendaRow(event: event)
                      }
                  }
              }
              .padding()
              .background(Color(.secondarySystemBackground))
              .clipShape(RoundedRectangle(cornerRadius: 16))
          }
      case .denied:
          calendarDeniedCard
      case .notDetermined:
          EmptyView() // initial refresh will drive state
      }
  }

  private func agendaRow(event: CalendarEventSummary) -> some View {
      Button {
          recordingInitialContext = RecordingRoomView.InitialContext(
              title: event.title,
              tags: event.attendees
          )
          isRecording = true
      } label: {
          HStack {
              VStack(alignment: .leading, spacing: 2) {
                  Text(event.title).font(.subheadline.weight(.medium))
                  Text(Self.timeFormatter.string(from: event.startDate))
                      .font(.caption)
                      .foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "mic.circle.fill")
                  .foregroundStyle(.tint)
          }
          .padding(.vertical, 6)
      }
      .buttonStyle(.plain)
  }

  private var calendarDeniedCard: some View {
      HStack(alignment: .top) {
          Image(systemName: "calendar.badge.exclamationmark")
              .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 4) {
              Text("Calendar access is off")
                  .font(.subheadline.weight(.semibold))
              Text("Enable calendar access in Settings to see today's agenda.")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              Button("Enable") {
                  if let url = URL(string: UIApplication.openSettingsURLString) {
                      UIApplication.shared.open(url)
                  }
              }
              .font(.caption.weight(.semibold))
              .padding(.top, 2)
          }
      }
      .padding()
      .background(Color(.secondarySystemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private static let timeFormatter: DateFormatter = {
      let f = DateFormatter()
      f.dateFormat = "HH:mm"
      return f
  }()
  ```

- [ ] **Step 5: Place the agenda section in the view body.**

  Inside the existing `VStack` / `ScrollView` in `DashboardView.body`, above the "Recent meetings" section, insert:

  ```swift
  agendaSection
  ```

- [ ] **Step 6: Build.**

  ⌘B. Expected: Build Succeeded.

- [ ] **Step 7: Simulator smoke test.**

  1. Run on iPhone 15 Simulator.
  2. Permission prompt should appear when Dashboard first shows.
  3. Allow: add a couple events to the Simulator Calendar app; re-launch DeepPocket; confirm agenda shows.
  4. Tap an event → RecordingRoomView opens pre-filled with event title + attendee tags.
  5. Dismiss, then deny permission via Settings → Calendars → DeepPocket → Off. Relaunch. Confirm "Calendar access is off" card renders, Enable button opens Settings.

- [ ] **Step 8: Checkpoint.**

  Zero warnings; smoke tests pass.

---

## Task 10: MeetingExportService — shareItems + exportAll

**Purpose:** Add `shareItems(for:)` returning markdown + audio URL for the per-meeting share sheet, and `exportAll()` producing a zip of markdown files with the agreed naming convention.

**Files:**
- Modify: `NoteCrux/Services/MeetingExportService.swift`

- [ ] **Step 1: Add `shareItems(for:)`.**

  At the end of `enum MeetingExportService` (before the closing `}`), add:

  ```swift
      /// Items suitable for presenting in a `UIActivityViewController`.
      /// Writes the markdown to a temp file so it travels nicely to Mail, Files, Messages.
      static func shareItems(for meeting: Meeting) throws -> [Any] {
          let markdown = markdown(for: meeting)
          let tempDir = FileManager.default.temporaryDirectory
          let safeTitle = sanitizedFilenameSegment(meeting.title)
          let datePart = isoDate(meeting.createdAt)
          let mdURL = tempDir.appendingPathComponent("\(safeTitle)__\(datePart).md")
          try markdown.write(to: mdURL, atomically: true, encoding: .utf8)

          var items: [Any] = [mdURL]
          if let audioPath = meeting.audioFilePath {
              let audioURL = URL(fileURLWithPath: audioPath)
              if FileManager.default.fileExists(atPath: audioURL.path) {
                  items.append(audioURL)
              }
          }
          return items
      }
  ```

- [ ] **Step 2: Add `exportAll()`.**

  Append:

  ```swift
      /// Produces a zip of markdown files (one per meeting) in a temp directory.
      /// Files are named `<sanitized-title>__<ISO-date>.md`.
      /// Returns the zip URL.
      static func exportAll(_ meetings: [Meeting]) throws -> URL {
          let tempDir = FileManager.default.temporaryDirectory
          let stageDir = tempDir.appendingPathComponent("deeppocket-export-\(UUID().uuidString)", isDirectory: true)
          try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)

          for meeting in meetings {
              let safeTitle = sanitizedFilenameSegment(meeting.title)
              let datePart = isoDate(meeting.createdAt)
              let fileURL = stageDir.appendingPathComponent("\(safeTitle)__\(datePart).md")
              let md = markdown(for: meeting)
              try md.write(to: fileURL, atomically: true, encoding: .utf8)
          }

          let zipURL = tempDir.appendingPathComponent("DeepPocket-Export-\(isoDate(Date())).zip")
          try zipDirectory(stageDir, to: zipURL)
          return zipURL
      }

      private static func sanitizedFilenameSegment(_ raw: String) -> String {
          let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
          let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
          let scalars = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
          let collapsed = String(scalars).replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
          let stripped = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
          return stripped.isEmpty ? "Untitled" : stripped
      }

      private static func isoDate(_ date: Date) -> String {
          let f = DateFormatter()
          f.dateFormat = "yyyy-MM-dd"
          f.calendar = Calendar(identifier: .gregorian)
          f.locale = Locale(identifier: "en_US_POSIX")
          f.timeZone = TimeZone.current
          return f.string(from: date)
      }

      /// Zips the given directory using Foundation's NSFileCoordinator via archive-by-copy.
      /// Uses `NSFileCoordinator.coordinate(readingItemAt:options:.forUploading, ...)`, which
      /// produces a zip archive suitable for the share sheet.
      private static func zipDirectory(_ source: URL, to destination: URL) throws {
          let coordinator = NSFileCoordinator()
          var coordError: NSError?
          var resultURL: URL?
          coordinator.coordinate(readingItemAt: source, options: [.forUploading], error: &coordError) { tmpURL in
              do {
                  if FileManager.default.fileExists(atPath: destination.path) {
                      try FileManager.default.removeItem(at: destination)
                  }
                  try FileManager.default.copyItem(at: tmpURL, to: destination)
                  resultURL = destination
              } catch {
                  coordError = error as NSError
              }
          }
          if let err = coordError { throw err }
          guard resultURL != nil else {
              throw NSError(
                  domain: "MeetingExportService",
                  code: -1,
                  userInfo: [NSLocalizedDescriptionKey: "Zip archive creation failed."]
              )
          }
      }
  ```

- [ ] **Step 3: Build.**

  ⌘B. Expected: Build Succeeded.

- [ ] **Step 4: Checkpoint.**

  Zero warnings. No call sites yet.

---

## Task 11: MeetingShareSheet view

**Purpose:** SwiftUI wrapper for `UIActivityViewController` used by the per-meeting share button.

**Files:**
- Create: `NoteCrux/Views/MeetingShareSheet.swift`

- [ ] **Step 1: Create the file.**

  Create `NoteCrux/Views/MeetingShareSheet.swift`:

  ```swift
  import SwiftUI
  import UIKit

  struct MeetingShareSheet: UIViewControllerRepresentable {
      let items: [Any]

      func makeUIViewController(context: Context) -> UIActivityViewController {
          UIActivityViewController(activityItems: items, applicationActivities: nil)
      }

      func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
  }
  ```

- [ ] **Step 2: Build.**

  ⌘B. Expected: Build Succeeded.

- [ ] **Step 3: Checkpoint.**

  Zero warnings.

---

## Task 12: InsightView — per-meeting share button

**Purpose:** Add a share button to the per-meeting detail view. Presents `MeetingShareSheet` with markdown + audio.

**Files:**
- Modify: `NoteCrux/Views/InsightView.swift`

- [ ] **Step 1: Add state for sheet + error.**

  Near the existing `@State private var selectedTab: DetailTab` declarations, add:

  ```swift
  @State private var shareItems: [Any]? = nil
  @State private var shareError: String? = nil
  ```

- [ ] **Step 2: Add toolbar share button.**

  Add a `.toolbar` modifier to the body if not already present (adapt if toolbar exists — just add a new `ToolbarItem`):

  ```swift
  .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
          Button {
              do {
                  shareItems = try MeetingExportService.shareItems(for: meeting)
              } catch {
                  shareError = error.localizedDescription
                  NoteCruxLog.export.debug("InsightView share failed: \(String(describing: error), privacy: .public)")
              }
          } label: {
              Image(systemName: "square.and.arrow.up")
          }
      }
  }
  .sheet(item: Binding(
      get: { shareItems.map { ShareItemsWrapper(items: $0) } },
      set: { shareItems = $0?.items }
  )) { wrapper in
      MeetingShareSheet(items: wrapper.items)
  }
  .alert("Could not prepare share", isPresented: Binding(
      get: { shareError != nil },
      set: { if !$0 { shareError = nil } }
  )) {
      Button("OK", role: .cancel) {}
  } message: {
      Text(shareError ?? "")
  }
  ```

- [ ] **Step 3: Add the wrapper type.**

  At the bottom of `InsightView.swift`, outside the struct, add:

  ```swift
  private struct ShareItemsWrapper: Identifiable {
      let id = UUID()
      let items: [Any]
  }
  ```

- [ ] **Step 4: Build.**

  ⌘B. Expected: Build Succeeded.

- [ ] **Step 5: Simulator smoke test.**

  1. Open an existing meeting → `InsightView` shows.
  2. Tap share icon in top right.
  3. Activity sheet appears with options (Save to Files, Copy, Mail, Messages).
  4. Save markdown to Files → open it → confirm content.

- [ ] **Step 6: Checkpoint.**

  Zero warnings; smoke test passes.

---

## Task 13: SettingsView — "Export all meetings" button

**Purpose:** Bulk export entry point in Settings.

**Files:**
- Modify: `NoteCrux/Views/SettingsView.swift`

- [ ] **Step 1: Add state + meetings query.**

  Near the top of `SettingsView`, add:

  ```swift
  @Query(sort: \Meeting.createdAt, order: .reverse) private var allMeetings: [Meeting]
  @State private var bulkExportURL: URL? = nil
  @State private var bulkExportError: String? = nil
  @State private var isExporting = false
  ```

- [ ] **Step 2: Add the section inside the existing form.**

  Add this section near the existing backup section (search for "Backup" or "Export" in `SettingsView`):

  ```swift
  Section("Bulk export") {
      Button {
          Task {
              isExporting = true
              defer { isExporting = false }
              do {
                  bulkExportURL = try MeetingExportService.exportAll(allMeetings)
              } catch {
                  bulkExportError = error.localizedDescription
                  NoteCruxLog.export.debug("Bulk export failed: \(String(describing: error), privacy: .public)")
              }
          }
      } label: {
          HStack {
              Text(isExporting ? "Preparing archive…" : "Export all meetings")
              Spacer()
              if isExporting {
                  ProgressView()
              } else {
                  Image(systemName: "arrow.up.doc.on.clipboard")
              }
          }
      }
      .disabled(isExporting || allMeetings.isEmpty)
      Text("Creates a zip of markdown files. Audio files are available via the per-meeting share button.")
          .font(.caption)
          .foregroundStyle(.secondary)
  }
  .sheet(item: Binding(
      get: { bulkExportURL.map { BulkExportWrapper(url: $0) } },
      set: { bulkExportURL = $0?.url }
  )) { wrapper in
      MeetingShareSheet(items: [wrapper.url])
  }
  .alert("Export failed", isPresented: Binding(
      get: { bulkExportError != nil },
      set: { if !$0 { bulkExportError = nil } }
  )) {
      Button("OK", role: .cancel) {}
  } message: {
      Text(bulkExportError ?? "")
  }
  ```

- [ ] **Step 3: Add the wrapper type.**

  At the bottom of `SettingsView.swift`:

  ```swift
  private struct BulkExportWrapper: Identifiable {
      let id = UUID()
      let url: URL
  }
  ```

- [ ] **Step 4: Build.**

  ⌘B. Expected: Build Succeeded.

- [ ] **Step 5: Simulator smoke test.**

  1. Settings → Bulk export → Export all meetings.
  2. Wait for "Preparing archive…" → share sheet appears.
  3. Save to Files → open via Files app → should unzip into per-meeting `.md` files.

- [ ] **Step 6: Checkpoint.**

  Zero warnings; smoke test passes.

---

## Task 14: DeepPocketIntents — the four AppIntents

**Purpose:** Define `StartRecordingIntent`, `TodaysAgendaIntent`, `AskDeepPocketIntent`, `LastMeetingDecisionsIntent`.

**Files:**
- Create: `NoteCrux/Intents/DeepPocketIntents.swift`

- [ ] **Step 1: Create the file with the four intents.**

  Create `NoteCrux/Intents/DeepPocketIntents.swift`:

  ```swift
  import AppIntents
  import Foundation
  import SwiftData

  // MARK: - Start Recording

  struct StartRecordingIntent: AppIntent {
      static let title: LocalizedStringResource = "Start DeepPocket recording"
      static let description = IntentDescription("Opens DeepPocket and begins a new meeting recording.")
      static var openAppWhenRun: Bool { true }

      @Dependency private var router: AppRouter

      func perform() async throws -> some IntentResult {
          router.requestRecording()
          NoteCruxLog.intents.debug("StartRecordingIntent fired")
          return .result()
      }
  }

  // MARK: - Today's Agenda

  struct TodaysAgendaIntent: AppIntent {
      static let title: LocalizedStringResource = "Today's agenda"
      static let description = IntentDescription("Reads today's scheduled calendar events.")
      static var openAppWhenRun: Bool { false }

      @MainActor
      func perform() async throws -> some IntentResult & ProvidesDialog {
          await CalendarImportService.shared.refresh()
          let events = CalendarImportService.shared.todaysEvents
          NoteCruxLog.intents.debug("TodaysAgendaIntent: \(events.count) events")

          if events.isEmpty {
              return .result(dialog: "You have nothing scheduled today.")
          }

          let formatter = DateFormatter()
          formatter.dateFormat = "h:mm a"
          let bullets = events.map { "\($0.title) at \(formatter.string(from: $0.startDate))" }
          let joined: String
          if bullets.count == 1 {
              joined = bullets[0]
          } else if bullets.count == 2 {
              joined = "\(bullets[0]) and \(bullets[1])"
          } else {
              joined = bullets.dropLast().joined(separator: ", ") + ", and " + bullets.last!
          }
          return .result(dialog: "You have \(events.count) event\(events.count == 1 ? "" : "s") today: \(joined).")
      }
  }

  // MARK: - Ask DeepPocket

  struct AskDeepPocketIntent: AppIntent {
      static let title: LocalizedStringResource = "Ask DeepPocket"
      static let description = IntentDescription("Answers a question using your meeting notes.")
      static var openAppWhenRun: Bool { false }

      @Parameter(title: "Question")
      var question: String

      @MainActor
      func perform() async throws -> some IntentResult & ProvidesDialog {
          let (meetings, tasks) = try await fetchMeetingsAndTasks()
          let engine = MeetingAssistantEngine()
          let result = await engine.answer(question: question, meetings: meetings, tasks: tasks)
          NoteCruxLog.intents.debug("AskDeepPocketIntent: usedFM=\(result.usedFM), cites=\(result.citedMeetings.count)")
          return .result(dialog: IntentDialog(stringLiteral: result.answer))
      }

      @MainActor
      private func fetchMeetingsAndTasks() async throws -> ([Meeting], [MeetingActionItem]) {
          let container = try ModelContainer(for: Meeting.self, MeetingFolder.self, MeetingActionItem.self)
          let context = ModelContext(container)
          let meetings = try context.fetch(FetchDescriptor<Meeting>())
          let tasks = try context.fetch(FetchDescriptor<MeetingActionItem>())
          return (meetings, tasks)
      }
  }

  // MARK: - Last Meeting Decisions

  struct LastMeetingDecisionsIntent: AppIntent {
      static let title: LocalizedStringResource = "Last meeting decisions"
      static let description = IntentDescription("Reads the decisions from your most recent meeting.")
      static var openAppWhenRun: Bool { false }

      @MainActor
      func perform() async throws -> some IntentResult & ProvidesDialog {
          let container = try ModelContainer(for: Meeting.self, MeetingFolder.self, MeetingActionItem.self)
          let context = ModelContext(container)
          var descriptor = FetchDescriptor<Meeting>(sortBy: [SortDescriptor(\Meeting.createdAt, order: .reverse)])
          descriptor.fetchLimit = 1
          let meetings = try context.fetch(descriptor)
          guard let meeting = meetings.first else {
              return .result(dialog: "You have no meetings yet.")
          }
          if meeting.decisions.isEmpty {
              return .result(dialog: "Your last meeting, \(meeting.title), did not record any decisions.")
          }
          let list = meeting.decisions.joined(separator: ". ")
          return .result(dialog: "From your last meeting, \(meeting.title): \(list).")
      }
  }
  ```

- [ ] **Step 2: Build.**

  ⌘B. Expected: Build Succeeded. If `@Dependency` errors for `AppRouter`, confirm Task 15 will register it — build order does not matter here because `@Dependency` is resolved at runtime.

- [ ] **Step 3: Checkpoint.**

  Zero warnings.

---

## Task 15: NoteCruxShortcuts + App entry wiring

**Purpose:** Register the four intents with the OS, own the `AppRouter`, inject dependencies, react to the router from `ContentView`, purge FM cache on background.

**Files:**
- Modify: `NoteCrux/Services/NoteCruxShortcuts.swift`
- Modify: `NoteCrux/NoteCruxApp.swift`
- Modify: `NoteCrux/ContentView.swift`

- [ ] **Step 1: Register the four intents in `NoteCruxShortcuts`.**

  Open `NoteCrux/Services/NoteCruxShortcuts.swift`. Replace the contents with:

  ```swift
  import AppIntents

  struct NoteCruxShortcuts: AppShortcutsProvider {
      static var appShortcuts: [AppShortcut] {
          AppShortcut(
              intent: StartRecordingIntent(),
              phrases: [
                  "Start a \(.applicationName) recording",
                  "Record a meeting in \(.applicationName)"
              ],
              shortTitle: "Start recording",
              systemImageName: "mic.circle.fill"
          )
          AppShortcut(
              intent: TodaysAgendaIntent(),
              phrases: [
                  "What's on my agenda in \(.applicationName)",
                  "Read my \(.applicationName) agenda"
              ],
              shortTitle: "Today's agenda",
              systemImageName: "calendar"
          )
          AppShortcut(
              intent: AskDeepPocketIntent(),
              phrases: [
                  "Ask \(.applicationName)",
                  "Ask my \(.applicationName) notes"
              ],
              shortTitle: "Ask DeepPocket",
              systemImageName: "bubble.left.and.bubble.right"
          )
          AppShortcut(
              intent: LastMeetingDecisionsIntent(),
              phrases: [
                  "What were my last \(.applicationName) decisions",
                  "Read decisions from my last \(.applicationName) meeting"
              ],
              shortTitle: "Last meeting decisions",
              systemImageName: "checkmark.seal"
          )
      }
  }
  ```

  The existing `StartDeepPocketMeetingIntent` struct defined in this file is superseded by the new `StartRecordingIntent` from Task 14 — delete the old `struct StartDeepPocketMeetingIntent: AppIntent { ... }` declaration at the top of this file.

- [ ] **Step 2: Own the `AppRouter` in `NoteCruxApp`.**

  Open `NoteCrux/NoteCruxApp.swift`. Add imports + state + inject:

  ```swift
  import SwiftUI
  import SwiftData
  import AppIntents

  @main
  struct NoteCruxApp: App {
      @State private var router = AppRouter()
      @Environment(\.scenePhase) private var scenePhase

      init() {
          // Make AppRouter available to AppIntents (resolves @Dependency in intents).
          AppDependencyManager.shared.add(dependency: router)

          // Announce shortcuts to the OS.
          NoteCruxShortcuts.updateAppShortcutParameters()
      }

      var body: some Scene {
          WindowGroup {
              ContentView()
                  .environment(router)
          }
          .modelContainer(for: [Meeting.self, MeetingFolder.self, MeetingActionItem.self])
          .onChange(of: scenePhase) { _, newValue in
              if newValue == .background {
                  FoundationModelClient.shared.purgeSessionCache()
              }
          }
      }
  }
  ```

  Note: `AppDependencyManager.shared.add(dependency:)` requires iOS 16.0+. Since the deployment target is 18.2, this is fine.

  Also note: the existing body of `NoteCruxApp` may differ — keep any existing modifiers (theme, analytics, etc.) that are already present; the additions are `@State private var router`, the `init`, `.environment(router)`, and the scenePhase observer.

- [ ] **Step 3: Consume router in `ContentView`.**

  In `ContentView.swift`, add:

  ```swift
  @Environment(AppRouter.self) private var router
  ```

  And add an `onChange` to react to recording requests. Near the other lifecycle modifiers in the body:

  ```swift
  .onChange(of: router.pendingRecordingRequest) { _, newValue in
      guard let request = router.consumeRecordingRequest() else { return }
      recordingInitialContext = RecordingRoomView.InitialContext(
          title: request.title ?? "",
          tags: request.tags
      )
      isRecording = true
  }
  ```

- [ ] **Step 4: Build.**

  ⌘B. Expected: Build Succeeded.

- [ ] **Step 5: Simulator smoke test.**

  1. Launch; background app; open iOS Settings → Shortcuts → DeepPocket. Expected: 4 shortcuts listed.
  2. Open iOS Shortcuts app → search "DeepPocket". Expected: 4 actions available.
  3. Run "Today's agenda" → expected spoken/visual result listing today's events or "nothing scheduled."
  4. Run "Start DeepPocket recording" → app launches and the recording sheet opens.
  5. Run "Ask DeepPocket" with parameter "what did we decide last meeting" → expected keyword-answer text on Simulator (FM unavailable).

- [ ] **Step 6: Checkpoint.**

  Zero warnings; smoke tests pass. If a shortcut doesn't appear in Settings, confirm the `NoteCruxShortcuts` type is the **only** `AppShortcutsProvider` in the target — AppIntents only allows one.

---

## Task 16: End-to-end smoke test (verification gate)

**Purpose:** The spec's §7 checklist, performed and recorded.

**Files:** None modified. Output: a notes file under `docs/superpowers/plans/notes/`.

- [ ] **Step 1: Heuristic path (Simulator).**

  Repeat Task 1 end-to-end on iPhone 15 Simulator iOS 18.2 (no Apple Intelligence). Confirm every tab populates for the scripted 90-second sample.

- [ ] **Step 2: FM path (physical device).**

  Run on iPhone 15 Pro or newer with Apple Intelligence enabled. Repeat the same recording.
  Expected: output is noticeably cleaner — summaries in full sentences, no stray sentence fragments, action items deduped, owner/deadline/priority fields accurate.
  Turn airplane mode ON → repeat a recording → confirm FM path still runs (true on-device) or falls back cleanly to heuristic.

- [ ] **Step 3: Long transcript.**

  On the Apple Intelligence device, at build time set a debug entry point (or just run a 10-min recording). Confirm:
  - Chunked run produces coherent summary.
  - Action items are deduped across chunks.
  - Cancellation: navigate away mid-generation → log shows "FM insight generation cancelled" (via Console.app filter on subsystem `works.kaspar.notecrux`, category `ai`).

- [ ] **Step 4: Calendar flows.**

  Grant + deny paths, as in Task 9 Step 7.

- [ ] **Step 5: Every Siri shortcut.**

  As in Task 15 Step 5, plus: invoke each shortcut from the iOS Shortcuts app. Confirm spoken dialog and/or app navigation for all four.

- [ ] **Step 6: Per-meeting share + bulk export.**

  As in Task 12 Step 5 and Task 13 Step 5.

- [ ] **Step 7: Record the results.**

  Write `docs/superpowers/plans/notes/2026-04-16-verification.md` with one section per checklist item: what was tested, device used, pass/fail, notes. If a step could not be performed (e.g., no Apple Intelligence device was available), state that explicitly — do not claim success.

- [ ] **Step 8: Final checkpoint.**

  Xcode: Clean Build Folder + Build + run on Simulator once more. Zero warnings, zero runtime crashes through the recording → dashboard → tasks → search → export loop.

---

## Self-review notes

Performed after writing, before handoff:

1. **Spec coverage** — every §2 in-scope item maps to a task:
   - FM for `LocalInsightGenerator` → Tasks 3, 4, 5.
   - FM for `MeetingAssistantEngine` → Tasks 3, 4, 6.
   - Calendar import + Dashboard agenda → Tasks 7, 8, 9.
   - Siri shortcuts → Tasks 14, 15.
   - Per-meeting share → Tasks 10, 11, 12.
   - Bulk export → Tasks 10, 13.
   - End-to-end smoke test → Tasks 1 (heuristic baseline) and 16 (final gate).
   - Concurrency guard → Task 5 Step 2.
   - Cancellation → Task 4 (chunked path uses `Task.checkCancellation`).
   - In-memory session cache → Task 4.
   - Logging boundary → Task 2 Step 1.
   - Citations cap at 3–5 → Task 6 Step 4.
   - Calendar denied deep-link → Task 9 Step 4.
   - Action-item dedupe normalization + fuzzy match → Task 4 Step 4.
   - AskDeepPocket ~2–4 sentence cap → Task 3 Step 4 (in the prompt) + Task 14 Step 1.
   - Bulk export filename convention → Task 10 Step 2.

2. **Placeholder scan** — no TBDs, no "implement later", every step includes real Swift code.

3. **Type consistency** — `FMInsightOutput`, `FMActionItemOutput`, `FMAnswerOutput`, `FoundationModelClient.MeetingContext`, `RecordingRoomView.InitialContext`, `AppRouter.RecordingRequest`, `AnswerResult` are each defined once and referenced consistently in later tasks. `MeetingExportService` is an `enum` (namespace) — confirmed matches the existing file.

4. **Scope check** — one spec, one plan, one working target. No sub-project decomposition needed.
