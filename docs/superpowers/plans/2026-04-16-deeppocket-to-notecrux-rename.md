# DeepPocket → NoteCrux Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the project end-to-end from DeepPocket to NoteCrux with no functional changes, so the launch-time brand is consistent across Xcode identifiers, Siri phrases, logging, user-visible strings, and the (not-yet-created) StoreKit product IDs.

**Architecture:** Phase-ordered branch work. Non-breaking string / symbol edits first (project stays buildable after each commit); filesystem and `project.pbxproj` changes next; documentation last. Branch is `rename/notecrux`; landed on `main` as a single squash commit.

**Tech Stack:** Xcode 16.2 filesystem-synchronized project, Swift 5.9, iOS 18.2 target, git CLI (no `gh`).

**Adaptations to plan defaults:**
- **No TDD / no XCTest target.** Verification = `xcodebuild` compile success after each step.
- **Commits on `rename/notecrux` branch**, not main. Squash-merged to main at the end.
- **Bundle ID reality-check:** actual current bundle ID in `project.pbxproj` is `com.KasparWorks.DeepPocket-ios` (NOT `works.kaspar.deeppocket` — that's only the logger subsystem string). Rename target: `com.KasparWorks.NoteCrux`.

**Working tree:** `/Users/bistrokaspar/projects/Kasparworks/DeepPocket.ios`
**Spec:** `docs/superpowers/specs/2026-04-16-deeppocket-to-notecrux-rename-design.md`

---

## File structure

**Renamed files (6):**
- `DeepPocket.ios/DeepPocket_iosApp.swift` → `NoteCrux/NoteCruxApp.swift`
- `DeepPocket.ios/DeepPocketLog.swift` → `NoteCrux/NoteCruxLog.swift`
- `DeepPocket.ios/DeepPocket_ios.entitlements` → `NoteCrux/NoteCrux.entitlements`
- `DeepPocket.ios/Services/DeepPocketShortcuts.swift` → `NoteCrux/Services/NoteCruxShortcuts.swift`
- `DeepPocket.ios/Views/DeepPocketTheme.swift` → `NoteCrux/Views/NoteCruxTheme.swift`
- Scheme XML: `DeepPocket.ios.xcscheme` → `NoteCrux.xcscheme`

**Renamed folders (2):**
- `DeepPocket.ios.xcodeproj/` → `NoteCrux.xcodeproj/`
- `DeepPocket.ios/` → `NoteCrux/`

**Modified files (string / symbol edits, no filename change):**
- All 21 `.swift` files that reference "DeepPocket" in some form (enumerated per task)
- `DeepPocket.ios.xcodeproj/project.pbxproj` (the big one)
- Both superpowers docs in `docs/superpowers/`

---

## Task ordering

```
Task 1 (Branch + baseline)
Task 2 (Internal strings: logger subsystem + DispatchQueue labels + prompt)
Task 3 (Swift symbol renames inside files — NOT files yet)
Task 4 (User-visible Text() / dialog() / description strings)
Task 5 (Fallback / filename default strings)
Task 6 (Entitlements file rename + CODE_SIGN_ENTITLEMENTS)
Task 7 (Swift file renames — names only, folder unchanged)
Task 8 (Root folder rename + pbxproj path fixups)
Task 9 (Xcodeproj folder rename + scheme rename + bundle ID + Info.plist keys)
Task 10 (Docs rename + in-doc rewrites)
Task 11 (Search-and-verify + squash merge + remote)
```

---

## Task 1: Branch & baseline

**Purpose:** Create the rename branch and confirm the project builds as-is.

- [ ] **Step 1: Create the branch.**

  ```bash
  cd /Users/bistrokaspar/projects/Kasparworks/DeepPocket.ios
  git checkout -b rename/notecrux
  ```

  Expected: `Switched to a new branch 'rename/notecrux'`.

- [ ] **Step 2: Verify baseline build.**

  ```bash
  xcodebuild -project DeepPocket.ios.xcodeproj -scheme DeepPocket.ios \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
  ```

  Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: No commit — baseline has no new work.**

---

## Task 2: Internal strings (logger subsystem + queue labels + LLM prompt)

**Purpose:** Swap the three internal string literals that still say "deeppocket" to "notecrux". These are in-place edits inside existing files. Project builds after each.

**Files:**
- Modify: `DeepPocket.ios/DeepPocketLog.swift:5`
- Modify: `DeepPocket.ios/Services/FoundationModelClient.swift:123` and `:251`
- Modify: `DeepPocket.ios/Services/LocalInsightGenerator.swift:6`
- Modify: `DeepPocket.ios/AppRouter.swift` (line 26 is the logger call; the DispatchQueue label, if any, check lines 10–20)

- [ ] **Step 1: Edit the logger subsystem literal.**

  In `DeepPocket.ios/DeepPocketLog.swift` line 5, change:
  ```swift
  static let subsystem = "works.kaspar.deeppocket"
  ```
  to:
  ```swift
  static let subsystem = "works.kaspar.notecrux"
  ```

- [ ] **Step 2: Edit the FoundationModelClient DispatchQueue label.**

  In `DeepPocket.ios/Services/FoundationModelClient.swift` line 123, change:
  ```swift
  private let cacheQueue = DispatchQueue(label: "works.kaspar.deeppocket.fm.cache")
  ```
  to:
  ```swift
  private let cacheQueue = DispatchQueue(label: "works.kaspar.notecrux.fm.cache")
  ```

- [ ] **Step 3: Edit the FoundationModelClient LLM system-prompt line.**

  In `DeepPocket.ios/Services/FoundationModelClient.swift` around line 251, change:
  ```swift
  You are DeepPocket, a concise meeting assistant.
  ```
  to:
  ```swift
  You are NoteCrux, a concise meeting assistant.
  ```

- [ ] **Step 4: Edit the LocalInsightGenerator DispatchQueue label.**

  In `DeepPocket.ios/Services/LocalInsightGenerator.swift` line 6, change:
  ```swift
  private let inflightQueue = DispatchQueue(label: "works.kaspar.deeppocket.insight.inflight")
  ```
  to:
  ```swift
  private let inflightQueue = DispatchQueue(label: "works.kaspar.notecrux.insight.inflight")
  ```

- [ ] **Step 5: Check AppRouter for a DispatchQueue label.**

  Grep: `grep -n "works.kaspar" DeepPocket.ios/AppRouter.swift`. If a DispatchQueue label appears, change its `deeppocket` segment to `notecrux`. If it only shows the `DeepPocketLog.intents.debug(...)` line at 26, nothing to do in this step.

- [ ] **Step 6: Build.**

  ```bash
  xcodebuild -project DeepPocket.ios.xcodeproj -scheme DeepPocket.ios \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit.**

  ```bash
  git add -A
  git commit -m "rename: internal strings (logger subsystem, queue labels, LLM prompt)"
  ```

---

## Task 3: Swift symbol renames (inside files; filenames untouched)

**Purpose:** Rename every `DeepPocket*` Swift symbol to `NoteCrux*`. Filenames don't change yet (that's Task 7). Doing this in its own commit because the diff touches many files.

**Files (modifications only; enumerated as the Edit targets per symbol):**

### 3a. `DeepPocketLog` → `NoteCruxLog`

- [ ] **Step 1: Rename the enum declaration.**

  In `DeepPocket.ios/DeepPocketLog.swift` line 4, change:
  ```swift
  enum DeepPocketLog {
  ```
  to:
  ```swift
  enum NoteCruxLog {
  ```

- [ ] **Step 2: Update every caller.**

  The callers are (confirmed by grep):
  - `DeepPocket.ios/AppRouter.swift:26`
  - `DeepPocket.ios/Services/CalendarImportService.swift:45`, `:87`
  - `DeepPocket.ios/Services/FoundationModelClient.swift:136`, `:150`, `:233`, `:238`, `:333` (and any on lines between these, inside the `#if canImport(FoundationModels)` block)
  - `DeepPocket.ios/Services/LocalInsightGenerator.swift:278`, `:281`
  - `DeepPocket.ios/Services/MeetingAssistantEngine.swift:47`
  - `DeepPocket.ios/Views/InsightView.swift:113`
  - `DeepPocket.ios/Views/SettingsView.swift:142`
  - `DeepPocket.ios/Intents/DeepPocketIntents.swift:17`, `:33`, `:69` (and any other `DeepPocketLog.intents.debug(...)` calls in that file)

  For each file, replace every occurrence of `DeepPocketLog` with `NoteCruxLog` (no other edits). Use Edit with `replace_all: true` on `DeepPocketLog` per file, confirming nothing else in that file matches.

### 3b. `DeepPocket_iosApp` → `NoteCruxApp`

- [ ] **Step 3: Rename the app struct.**

  In `DeepPocket.ios/DeepPocket_iosApp.swift` line 13, change:
  ```swift
  struct DeepPocket_iosApp: App {
  ```
  to:
  ```swift
  struct NoteCruxApp: App {
  ```

  The `@main` attribute immediately above stays. No other callers exist (this is the entry point).

  Also update the file-header comments on lines 2–3:
  ```swift
  //  DeepPocket_iosApp.swift
  //  DeepPocket.ios
  ```
  to:
  ```swift
  //  NoteCruxApp.swift
  //  NoteCrux
  ```

### 3c. `DeepPocketShortcuts` → `NoteCruxShortcuts`

- [ ] **Step 4: Rename the provider struct.**

  In `DeepPocket.ios/Services/DeepPocketShortcuts.swift` line 3, change:
  ```swift
  struct DeepPocketShortcuts: AppShortcutsProvider {
  ```
  to:
  ```swift
  struct NoteCruxShortcuts: AppShortcutsProvider {
  ```

- [ ] **Step 5: Update the caller in `DeepPocket_iosApp.swift`.**

  Line 25 currently reads:
  ```swift
  DeepPocketShortcuts.updateAppShortcutParameters()
  ```
  Change to:
  ```swift
  NoteCruxShortcuts.updateAppShortcutParameters()
  ```

### 3d. `DeepPocketTheme` → `NoteCruxTheme`

- [ ] **Step 6: Rename the enum.**

  In `DeepPocket.ios/Views/DeepPocketTheme.swift` line 6, change:
  ```swift
  enum DeepPocketTheme {
  ```
  to:
  ```swift
  enum NoteCruxTheme {
  ```

- [ ] **Step 7: Update callers.**

  Replace `DeepPocketTheme` with `NoteCruxTheme` in each of:
  - `DeepPocket.ios/ContentView.swift:27`
  - `DeepPocket.ios/Views/AssistantView.swift:23`
  - `DeepPocket.ios/Views/AppLockView.swift:14`
  - `DeepPocket.ios/Views/VaultView.swift:43`
  - `DeepPocket.ios/Views/ProInsightsView.swift:55`

### 3e. `DeepPocketBackup` → `NoteCruxBackup`

- [ ] **Step 8: Rename the backup struct.**

  In `DeepPocket.ios/Services/LocalBackupService.swift`:
  - Line 4: `struct DeepPocketBackup: Codable {` → `struct NoteCruxBackup: Codable {`
  - Line 57: `let backup = DeepPocketBackup(` → `let backup = NoteCruxBackup(`

### 3f. `AskDeepPocketIntent` → `AskNoteCruxIntent`

- [ ] **Step 9: Rename the intent struct.**

  In `DeepPocket.ios/Intents/DeepPocketIntents.swift` line 56:
  ```swift
  struct AskDeepPocketIntent: AppIntent {
  ```
  to:
  ```swift
  struct AskNoteCruxIntent: AppIntent {
  ```

  Also rename the section comment on line 54 from `// MARK: - Ask DeepPocket` to `// MARK: - Ask NoteCrux`.

- [ ] **Step 10: Update the caller in `DeepPocketShortcuts.swift` (now using old file name — it's renamed in Task 7).**

  Line 24 currently reads:
  ```swift
  intent: AskDeepPocketIntent(),
  ```
  Change to:
  ```swift
  intent: AskNoteCruxIntent(),
  ```

### 3g. Build + commit

- [ ] **Step 11: Build.**

  `xcodebuild ... build 2>&1 | tail -5` — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 12: Commit.**

  ```bash
  git add -A
  git commit -m "rename: Swift symbols (DeepPocketLog/Theme/Backup, AskDeepPocketIntent, etc.)"
  ```

---

## Task 4: User-visible `Text()` / dialog / description strings

**Purpose:** Update every "DeepPocket" the user actually sees (UI text, Siri dialogs, intent descriptions, permission rationales via Info.plist keys — the last one lands in Task 9 because it's in pbxproj).

- [ ] **Step 1: `OnboardingView.swift`.**

  In `DeepPocket.ios/Views/OnboardingView.swift`:
  - Line 62: `Text("DeepPocket")` → `Text("NoteCrux")`
  - Line 305: `subtitle: "Join DeepPocket for a premium meeting experience.",` → `subtitle: "Join NoteCrux for a premium meeting experience.",`

- [ ] **Step 2: `TasksView.swift`.**

  Line 177: `Text("DeepPocket")` → `Text("NoteCrux")`.

- [ ] **Step 3: `InsightView.swift`.**

  Line 221: `Text("DeepPocket")` → `Text("NoteCrux")`.

- [ ] **Step 4: `SettingsView.swift`.**

  - Line 51: `subtitle: "Use Face ID to secure DeepPocket",` → `subtitle: "Use Face ID to secure NoteCrux",`
  - Line 196: `Text("© 2024 DeepPocket AI Lab")` → `Text("© 2024 NoteCrux AI Lab")`
  - Line 223: `"Delete all local DeepPocket data?",` → `"Delete all local NoteCrux data?",`
  - Line 298: `Text("DeepPocket")` → `Text("NoteCrux")`
  - Line 537: `Text("DeepPocket is local-first encryption. Your financial data never leaves this device without your permission.")` → `Text("NoteCrux is local-first encryption. Your financial data never leaves this device without your permission.")`

- [ ] **Step 5: `AppLockView.swift`.**

  - Line 21: `Text("DeepPocket Locked")` → `Text("NoteCrux Locked")`
  - Line 71: `let success = await AppSecurity.unlockWithBiometrics(reason: "Unlock DeepPocket.")` → `let success = await AppSecurity.unlockWithBiometrics(reason: "Unlock NoteCrux.")`

- [ ] **Step 6: `DeepPocketIntents.swift` — intent titles, descriptions, dialogs.**

  - Line 8: `static let title: LocalizedStringResource = "Start DeepPocket recording"` → `"Start NoteCrux recording"`
  - Line 9: `static let description = IntentDescription("Opens DeepPocket and begins a new meeting recording.")` → `"Opens NoteCrux and begins a new meeting recording."`
  - Line 57: `static let title: LocalizedStringResource = "Ask DeepPocket"` → `"Ask NoteCrux"`

- [ ] **Step 7: `DeepPocketShortcuts.swift` — Siri shortcut phrases + shortTitle.**

  Line 29: `shortTitle: "Ask DeepPocket",` → `shortTitle: "Ask NoteCrux",`.

  The phrases that use `\(.applicationName)` auto-update once the display name changes in Task 9 — no edits needed there. If the file has any literal `"DeepPocket"` inside phrase strings, change to `"NoteCrux"`.

- [ ] **Step 8: `LocalInsightGenerator.swift` — user-visible fallback notes.**

  - Line 34: `paragraphNotes: "No transcript was captured, so DeepPocket could not generate notes.",` → `"... NoteCrux could not generate notes.",`
  - Line 121: same string → `"... NoteCrux could not generate notes."`

- [ ] **Step 9: Build.**

  `xcodebuild ... build 2>&1 | tail -5` — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 10: Commit.**

  ```bash
  git add -A
  git commit -m "rename: user-visible Text(), dialogs, intent descriptions"
  ```

---

## Task 5: Fallback & default filename strings

**Purpose:** Backup and export filenames, which surface to users via exported files.

- [ ] **Step 1: `LocalBackupService.swift`.**

  Line 70 currently:
  ```swift
  let fileURL = folderURL.appendingPathComponent("DeepPocket-Backup-\(Self.timestamp()).json")
  ```
  Change to:
  ```swift
  let fileURL = folderURL.appendingPathComponent("NoteCrux-Backup-\(Self.timestamp()).json")
  ```

- [ ] **Step 2: `MeetingExportService.swift`.**

  - Line 166: `return cleaned.isEmpty ? "DeepPocket-Meeting" : cleaned` → `return cleaned.isEmpty ? "NoteCrux-Meeting" : cleaned`
  - Line 211: `let zipURL = tempDir.appendingPathComponent("DeepPocket-Export-\(isoDate(Date())).zip")` → `"NoteCrux-Export-\(isoDate(Date())).zip"`

- [ ] **Step 3: Build.**

  `xcodebuild ... build 2>&1 | tail -5` — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit.**

  ```bash
  git add -A
  git commit -m "rename: export and backup filename defaults"
  ```

---

## Task 6: Entitlements file rename + `CODE_SIGN_ENTITLEMENTS`

**Purpose:** Rename the entitlements file and update the two pbxproj paths that reference it.

**Files:**
- Rename: `DeepPocket.ios/DeepPocket_ios.entitlements` → `DeepPocket.ios/NoteCrux.entitlements`
- Modify: `DeepPocket.ios.xcodeproj/project.pbxproj:247` and `:294`

- [ ] **Step 1: Git-rename the entitlements file.**

  ```bash
  git mv DeepPocket.ios/DeepPocket_ios.entitlements DeepPocket.ios/NoteCrux.entitlements
  ```

- [ ] **Step 2: Edit the two `CODE_SIGN_ENTITLEMENTS` entries.**

  In `DeepPocket.ios.xcodeproj/project.pbxproj`:
  - Line 247: `CODE_SIGN_ENTITLEMENTS = DeepPocket.ios/DeepPocket_ios.entitlements;` → `CODE_SIGN_ENTITLEMENTS = DeepPocket.ios/NoteCrux.entitlements;`
  - Line 294: same change.

  Note: folder is still `DeepPocket.ios/` at this stage — that folder renames in Task 8.

- [ ] **Step 3: Build.**

  `xcodebuild ... build 2>&1 | tail -5` — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit.**

  ```bash
  git add -A
  git commit -m "rename: entitlements file DeepPocket_ios.entitlements → NoteCrux.entitlements"
  ```

---

## Task 7: Swift file renames (names only; folder unchanged)

**Purpose:** Rename the five `.swift` filenames that contain "DeepPocket" in their name. Folder `DeepPocket.ios/` is untouched here — Task 8 does that. Filesystem-synchronized groups pick up the new files automatically; no pbxproj edits needed.

- [ ] **Step 1: Rename the five files via `git mv`.**

  ```bash
  git mv DeepPocket.ios/DeepPocket_iosApp.swift DeepPocket.ios/NoteCruxApp.swift
  git mv DeepPocket.ios/DeepPocketLog.swift DeepPocket.ios/NoteCruxLog.swift
  git mv DeepPocket.ios/Services/DeepPocketShortcuts.swift DeepPocket.ios/Services/NoteCruxShortcuts.swift
  git mv DeepPocket.ios/Views/DeepPocketTheme.swift DeepPocket.ios/Views/NoteCruxTheme.swift
  ```

  Note: `DeepPocket.ios/Intents/DeepPocketIntents.swift` is NOT renamed (its filename is generic-enough).

- [ ] **Step 2: Build.**

  `xcodebuild ... build 2>&1 | tail -5` — expect `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit.**

  ```bash
  git add -A
  git commit -m "rename: Swift file names (DeepPocket_iosApp/Log/Shortcuts/Theme → NoteCrux*)"
  ```

---

## Task 8: Root folder rename + pbxproj path fixups (highest risk)

**Purpose:** Rename `DeepPocket.ios/` → `NoteCrux/`. Update every pbxproj path reference.

**Files:**
- Move: `DeepPocket.ios/` → `NoteCrux/`
- Modify: `DeepPocket.ios.xcodeproj/project.pbxproj` (many lines)

- [ ] **Step 1: Move the folder.**

  ```bash
  git mv DeepPocket.ios NoteCrux
  ```

- [ ] **Step 2: Rewrite path references in pbxproj.**

  Every occurrence of `DeepPocket.ios/` (the source-root path) becomes `NoteCrux/`. The safe way: a single sed replacement on the whole file because the string is unambiguous.

  ```bash
  python3 -c "
  import pathlib
  p = pathlib.Path('DeepPocket.ios.xcodeproj/project.pbxproj')
  txt = p.read_text()
  txt = txt.replace('DeepPocket.ios/', 'NoteCrux/')
  p.write_text(txt)
  "
  ```

  Verify immediately:
  ```bash
  grep -n "DeepPocket.ios/" DeepPocket.ios.xcodeproj/project.pbxproj
  ```
  Expected: no matches. Any remaining must be investigated before proceeding.

- [ ] **Step 3: Also rewrite bare `DeepPocket.ios` identifiers (without trailing `/`) used as group/target references in pbxproj.**

  These are the group path `path = DeepPocket.ios;` and similar. Do a targeted pass:

  ```bash
  python3 -c "
  import pathlib, re
  p = pathlib.Path('DeepPocket.ios.xcodeproj/project.pbxproj')
  txt = p.read_text()
  # Replace bare-word DeepPocket.ios in pbxproj identifiers / values
  # (folder rename only; target/scheme/product come in Task 9)
  txt = re.sub(r'\\bDeepPocket\\.ios\\b(?![\\.\\w])', 'NoteCrux', txt)
  p.write_text(txt)
  "
  ```

  Verify: `grep -n 'DeepPocket.ios' DeepPocket.ios.xcodeproj/project.pbxproj` — any remaining references should be inspected.

- [ ] **Step 4: Open in Xcode for visual verification.**

  Open `DeepPocket.ios.xcodeproj` (still the old name until Task 9) in Xcode. In the file navigator, confirm no filenames are red (missing). If any are red, the `project.pbxproj` path fixup missed an entry — back out with `git reset --hard HEAD` and redo Steps 2–3 more carefully. Close Xcode before continuing.

- [ ] **Step 5: Build.**

  ```bash
  xcodebuild -project DeepPocket.ios.xcodeproj -scheme DeepPocket.ios \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit.**

  ```bash
  git add -A
  git commit -m "rename: root source folder DeepPocket.ios → NoteCrux (with pbxproj path fixups)"
  ```

---

## Task 9: Xcode project folder + scheme + bundle ID + Info.plist keys

**Purpose:** Rename the `.xcodeproj` folder, the scheme file, then update every remaining "DeepPocket" identifier inside pbxproj (bundle ID, target name, Info.plist keys, scheme XML refs).

**Files:**
- Move: `DeepPocket.ios.xcodeproj/` → `NoteCrux.xcodeproj/`
- Move: `NoteCrux.xcodeproj/xcshareddata/xcschemes/DeepPocket.ios.xcscheme` → `.../NoteCrux.xcscheme`
- Modify: `NoteCrux.xcodeproj/project.pbxproj` and `NoteCrux.xcscheme`

- [ ] **Step 1: Rename the xcodeproj folder.**

  ```bash
  git mv DeepPocket.ios.xcodeproj NoteCrux.xcodeproj
  ```

- [ ] **Step 2: Rename the scheme file.**

  ```bash
  git mv NoteCrux.xcodeproj/xcshareddata/xcschemes/DeepPocket.ios.xcscheme \
         NoteCrux.xcodeproj/xcshareddata/xcschemes/NoteCrux.xcscheme
  ```

- [ ] **Step 3: Update `PRODUCT_BUNDLE_IDENTIFIER` in pbxproj.**

  Every occurrence of `com.KasparWorks.DeepPocket-ios` → `com.KasparWorks.NoteCrux`:

  ```bash
  python3 -c "
  import pathlib
  p = pathlib.Path('NoteCrux.xcodeproj/project.pbxproj')
  txt = p.read_text()
  txt = txt.replace('com.KasparWorks.DeepPocket-ios', 'com.KasparWorks.NoteCrux')
  p.write_text(txt)
  "
  ```

- [ ] **Step 4: Update remaining bare-name references in pbxproj.**

  Target name, product name, and remaining `DeepPocket.ios` bare identifiers that may have survived Task 8:

  ```bash
  python3 -c "
  import pathlib
  p = pathlib.Path('NoteCrux.xcodeproj/project.pbxproj')
  txt = p.read_text()
  # Target/scheme/product names
  txt = txt.replace('DeepPocket.ios', 'NoteCrux')
  p.write_text(txt)
  "
  ```

- [ ] **Step 5: Update Info.plist usage description strings in pbxproj.**

  Each `INFOPLIST_KEY_NS*UsageDescription` value references "DeepPocket". Rewrite:

  ```bash
  python3 -c "
  import pathlib
  p = pathlib.Path('NoteCrux.xcodeproj/project.pbxproj')
  txt = p.read_text()
  txt = txt.replace('DeepPocket can create local calendar events from your meetings when you ask it to.',
                    'NoteCrux can create local calendar events from your meetings when you ask it to.')
  txt = txt.replace('DeepPocket uses Face ID to protect your private meeting vault.',
                    'NoteCrux uses Face ID to protect your private meeting vault.')
  txt = txt.replace('DeepPocket records meeting audio locally to transcribe it on this device.',
                    'NoteCrux records meeting audio locally to transcribe it on this device.')
  txt = txt.replace('DeepPocket can add meeting tasks to Reminders when you ask it to.',
                    'NoteCrux can add meeting tasks to Reminders when you ask it to.')
  txt = txt.replace('DeepPocket uses on-device speech recognition to create private meeting transcripts.',
                    'NoteCrux uses on-device speech recognition to create private meeting transcripts.')
  p.write_text(txt)
  "
  ```

- [ ] **Step 6: Update the scheme XML.**

  Replace every `DeepPocket.ios` inside the scheme file:

  ```bash
  python3 -c "
  import pathlib
  p = pathlib.Path('NoteCrux.xcodeproj/xcshareddata/xcschemes/NoteCrux.xcscheme')
  txt = p.read_text()
  txt = txt.replace('DeepPocket.ios', 'NoteCrux')
  p.write_text(txt)
  "
  ```

- [ ] **Step 7: Verify target/scheme/Info.plist linkage.**

  Open `NoteCrux.xcodeproj` in Xcode. Verify:
  - Target name appears as `NoteCrux` in target list.
  - Scheme `NoteCrux` is selectable.
  - Target → Build Settings → Info.plist path resolves (not red).
  - Scheme → Manage Schemes → `BuildableName` in the `NoteCrux` scheme is `NoteCrux.app`.

  Close Xcode before building.

- [ ] **Step 8: Build with the new project/scheme names.**

  ```bash
  xcodebuild -project NoteCrux.xcodeproj -scheme NoteCrux \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit.**

  ```bash
  git add -A
  git commit -m "rename: xcodeproj folder, scheme, target, bundle ID, Info.plist keys"
  ```

---

## Task 10: Documentation rename + in-doc rewrites

**Purpose:** Rename the two superpowers docs + update their titles and in-doc references to bundle IDs / logger subsystem / queue labels.

- [ ] **Step 1: Rename the spec file.**

  ```bash
  git mv docs/superpowers/specs/2026-04-16-deeppocket-ai-wiring-design.md \
         docs/superpowers/specs/2026-04-16-notecrux-ai-wiring-design.md
  ```

- [ ] **Step 2: Rename the plan file.**

  ```bash
  git mv docs/superpowers/plans/2026-04-16-deeppocket-ai-wiring.md \
         docs/superpowers/plans/2026-04-16-notecrux-ai-wiring.md
  ```

- [ ] **Step 3: Rewrite in-doc title of the spec.**

  In `docs/superpowers/specs/2026-04-16-notecrux-ai-wiring-design.md`, change the H1:
  ```markdown
  # DeepPocket.ios — AI Wiring & Orphan Service Integration
  ```
  to:
  ```markdown
  # NoteCrux — AI Wiring & Orphan Service Integration
  ```

- [ ] **Step 4: Rewrite in-doc references to identifiers in the spec.**

  Replace inside the spec file:
  - `works.kaspar.deeppocket` → `works.kaspar.notecrux`
  - `DeepPocket.ios` (as module/folder name) → `NoteCrux`
  - `DeepPocketLog` → `NoteCruxLog`

  Bulk replace where each is unambiguous; inspect visually for context.

- [ ] **Step 5: Rewrite in-doc title of the plan.**

  In `docs/superpowers/plans/2026-04-16-notecrux-ai-wiring.md`, change the H1:
  ```markdown
  # DeepPocket.ios AI Wiring & Orphan Integration Implementation Plan
  ```
  to:
  ```markdown
  # NoteCrux AI Wiring & Orphan Integration Implementation Plan
  ```

- [ ] **Step 6: Rewrite in-doc identifier references in the plan.**

  Replace inside the plan file the same identifiers as Step 4. This file has the most textual references — especially the `FoundationModelClient` code snippets and the task-step commands that use the old folder/project names. Those are historical records of what was done at the time; rewriting them is cosmetic but desirable for consistency.

  Pragmatic approach: scoped find/replace for:
  - `DeepPocket.ios/` → `NoteCrux/`
  - `DeepPocket.ios.xcodeproj` → `NoteCrux.xcodeproj`
  - `works.kaspar.deeppocket` → `works.kaspar.notecrux`
  - `DeepPocket_iosApp` → `NoteCruxApp`
  - `DeepPocketLog` → `NoteCruxLog`
  - `DeepPocketShortcuts` → `NoteCruxShortcuts`

- [ ] **Step 7: Commit.**

  ```bash
  git add -A
  git commit -m "rename: docs (spec + plan filenames and in-doc references)"
  ```

---

## Task 11: Search-and-verify + squash merge + remote update

**Purpose:** The final verification + merge to main.

- [ ] **Step 1: Grep for leftover "DeepPocket" in source.**

  ```bash
  grep -rni "deeppocket" NoteCrux/ 2>&1 | head -20
  ```
  Expected: zero hits. If anything comes up, fix it inline and amend the most recent commit (`git commit --amend --no-edit` after `git add`).

- [ ] **Step 2: Grep for leftover "DeepPocket" in xcodeproj.**

  ```bash
  grep -rn "DeepPocket" NoteCrux.xcodeproj 2>&1 | head -20
  ```
  Expected: zero hits.

- [ ] **Step 3: Grep for leftover logger subsystem / bundle ID.**

  ```bash
  grep -rn "works\.kaspar\.deeppocket" . 2>&1 | head -10
  grep -rn "com\.KasparWorks\.DeepPocket" . 2>&1 | head -10
  ```
  Expected: zero hits outside historical references.

- [ ] **Step 4: Grep for old symbol names.**

  ```bash
  grep -rn "DeepPocket_iosApp\|DeepPocketLog\|DeepPocketShortcuts\|DeepPocketTheme\|DeepPocketBackup\|AskDeepPocketIntent\|DeepPocket_ios\.entitlements" . 2>&1 | head -20
  ```
  Expected: zero hits.

- [ ] **Step 5: Confirm bundle ID rewrite.**

  ```bash
  grep "PRODUCT_BUNDLE_IDENTIFIER" NoteCrux.xcodeproj/project.pbxproj
  ```
  Expected: every entry reads `PRODUCT_BUNDLE_IDENTIFIER = "com.KasparWorks.NoteCrux";`.

- [ ] **Step 6: Final clean build.**

  ```bash
  xcodebuild -project NoteCrux.xcodeproj -scheme NoteCrux \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO clean build 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Squash-merge to main.**

  ```bash
  git checkout main
  git merge --squash rename/notecrux
  git commit -m "$(cat <<'EOF'
  rename: DeepPocket → NoteCrux (full rebrand)

  Renames the project end-to-end with no functional changes:
  - Bundle ID com.KasparWorks.DeepPocket-ios → com.KasparWorks.NoteCrux
  - Xcode project/target/scheme/root folder → NoteCrux
  - App entry struct, logger enum, theme enum, backup struct, shortcuts
    provider, AskDeepPocket intent — all renamed
  - All user-visible strings, Siri dialogs, intent descriptions
  - Info.plist usage descriptions, backup/export filename defaults
  - Logger subsystem works.kaspar.deeppocket → works.kaspar.notecrux
  - Docs (spec + plan) renamed and rewritten

  Out of scope: git history rewrite (prior 17 commits remain accurate
  historical record).

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

- [ ] **Step 8: Update the git remote.**

  ```bash
  git remote set-url origin git@github.com:kaspar-works/NoteCrux_ios.git
  git remote -v
  ```
  Expected: remote shows the new URL.

- [ ] **Step 9: Delete the rename branch locally.**

  ```bash
  git branch -D rename/notecrux
  ```

- [ ] **Step 10: Push to main (only after the user confirms the GitHub repo rename has taken effect).**

  Ask the user to confirm `https://github.com/kaspar-works/NoteCrux_ios` loads in the browser before pushing.

  ```bash
  git push origin main
  ```
  Expected: successful push.

---

## Self-review notes

Run after writing, before handoff:

1. **Spec coverage** — every §2 in-scope item maps to a task:
   - Bundle ID change → Task 9 Steps 3, 5.
   - Xcode project/target/scheme/folder renames → Tasks 8 + 9.
   - App entry struct, logger enum, theme enum, backup struct, shortcuts provider, ask intent → Task 3.
   - Entitlements filename → Task 6.
   - StoreKit namespace (reserved) → no code today; noted in docs (Task 10).
   - Info.plist permission strings → Task 9 Step 5.
   - User-visible Text/dialogs/descriptions → Task 4.
   - Siri phrases / shortTitle → Task 4 Step 7 + Task 3 Step 4 for `AppShortcut(intent: ...)`.
   - Logger subsystem + queue labels + LLM prompt → Task 2.
   - Backup / export filenames → Task 5.
   - Docs rename → Task 10.
   - Search-and-verify → Task 11 Steps 1–5.
   - Squash merge + remote update → Task 11 Steps 7–10.
   - Per-phase rollback via `git reset --hard <last-green-commit>` → applies to every task; documented in spec §5.

2. **Placeholder scan** — no TBDs, every step has a concrete command or code diff.

3. **Type consistency** — `NoteCruxLog`, `NoteCruxApp`, `NoteCruxShortcuts`, `NoteCruxTheme`, `NoteCruxBackup`, `AskNoteCruxIntent` all defined in Task 3, referenced consistently in later tasks and in the verify step.

4. **Scope check** — single initiative, one branch, 11 tasks, squash merge. No sub-project needed.
