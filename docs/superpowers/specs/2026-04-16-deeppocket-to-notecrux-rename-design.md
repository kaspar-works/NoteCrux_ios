# DeepPocket → NoteCrux Rename

**Date:** 2026-04-16
**Status:** Approved pending implementation and user review

## 1. Goal

Rename the project end-to-end from DeepPocket to NoteCrux, with no functional changes, before any monetization work lands. The rename is motivated by launch-time brand consistency across Xcode identifiers, Siri phrases, logging subsystems, user-visible strings, and the (not-yet-created) StoreKit product IDs.

## 2. Scope

### 2.1 In scope — identifiers & build

- **Bundle ID:** `com.KasparWorks.DeepPocket-ios` → `com.KasparWorks.NoteCrux` (keeps the existing `com.KasparWorks.*` reverse-DNS namespace so signing profiles and App Store team setup keep working identically; only the product segment changes).
- **Xcode project filename:** `DeepPocket.ios.xcodeproj` → `NoteCrux.xcodeproj`.
- **Xcode target name:** `DeepPocket.ios` → `NoteCrux`.
- **Xcode scheme name:** `DeepPocket.ios` → `NoteCrux`.
- **Xcode root source folder:** `DeepPocket.ios/` → `NoteCrux/`.
- **App entry struct:** `DeepPocket_iosApp` → `NoteCruxApp`.
- **Entitlements filename:** `DeepPocket_ios.entitlements` → `NoteCrux.entitlements` (content unchanged — only two sandbox flags, no app groups / keychain sharing / associated domains exist).
- **StoreKit namespace** (reserved now, used during monetization): product IDs follow the bundle ID namespace → `com.KasparWorks.NoteCrux.*`. No `.storekit` configuration file exists yet; first product will be `com.KasparWorks.NoteCrux.pro.monthly`.
- **Info.plist** (auto-generated via `INFOPLIST_KEY_*` in `project.pbxproj`): update `CFBundleDisplayName`, `CFBundleName`, and every `NSxxxUsageDescription` that mentions DeepPocket.

Naming is standardized: no `.ios` suffix appears anywhere after the rename. Target, scheme, display name, product name, and root folder are all exactly `NoteCrux`.

### 2.2 In scope — user-visible strings

- App display name "DeepPocket" → "NoteCrux" (everywhere it appears).
- `OnboardingView` copy, `SettingsView` text, all error / alert messages.
- Permission usage description strings in the auto-generated Info.plist: microphone, speech recognition, calendars, reminders, Face ID.

### 2.3 In scope — Siri & AppIntents

- `AppShortcutsProvider` struct rename: `DeepPocketShortcuts` → `NoteCruxShortcuts`.
- All registered phrases and `shortTitle:` strings containing "DeepPocket" (e.g., "Ask DeepPocket" → "Ask NoteCrux"). Phrases using `\(.applicationName)` self-update.
- Each `AppIntent`'s `title`, `description`, and spoken `dialog(...)` strings.
- Any upgrade / spoken strings that will be added during monetization follow the new brand from day one.

### 2.4 In scope — internal strings (no behavior change)

- Logger subsystem `"works.kaspar.deeppocket"` → `"works.kaspar.notecrux"` (inside `NoteCruxLog.swift`). This is a Swift-source string, independent of the bundle ID — chosen at project start to use `works.kaspar.*` while the bundle ID uses `com.KasparWorks.*`. We keep the logger's `works.kaspar.*` namespace for continuity; only the product segment (`deeppocket` → `notecrux`) changes.
- DispatchQueue labels: `"works.kaspar.deeppocket.fm.cache"`, `"works.kaspar.deeppocket.insight.inflight"`, and the one in `AppRouter.swift`.
- Backup filename prefix in `LocalBackupService.swift`: `DeepPocket-Backup-*.json` → `NoteCrux-Backup-*.json`.
- Export filename defaults in `MeetingExportService.swift`: `"DeepPocket-Meeting"` fallback → `"NoteCrux-Meeting"`; `DeepPocket-Export-*.zip` → `NoteCrux-Export-*.zip`.
- LLM system prompt in `FoundationModelClient.swift:251`: `"You are DeepPocket, ..."` → `"You are NoteCrux, ..."` (affects how the model refers to itself in generated answers).

### 2.5 In scope — documentation & artifacts

- Spec filename `docs/superpowers/specs/2026-04-16-deeppocket-ai-wiring-design.md` → `...-notecrux-ai-wiring-design.md` + update in-doc title and references to bundle IDs, logger subsystem, queue labels.
- Plan filename `docs/superpowers/plans/2026-04-16-deeppocket-ai-wiring.md` → same treatment.
- No README, screenshots, or generated artifacts exist in the repo today.

### 2.6 In scope — git / remote

- GitHub repo rename `DeepPocket_ios` → `NoteCrux_ios` (user performs via github.com UI or `gh repo rename`).
- Local remote URL updated via `git remote set-url origin git@github.com:kaspar-works/NoteCrux_ios.git` (HTTPS form acceptable).

### 2.7 Out of scope

- **Any behavior change beyond rename and identifier / string updates** — this is a pure rename initiative, not a cleanup sprint.
- Rewriting git history. The existing 17 commits remain "DeepPocket" — accurate historical record; the rename is a forward-looking merge commit.
- Creating a new GitHub repo and re-pushing — we rename the existing one.
- App Store Connect work (no listing today).
- Swift Package Manager changes (none exist).
- Claude Code assistant memory files under `~/.claude/projects/...` — these are external assistant artifacts, not part of the repo. Updated separately post-rename.

## 3. Architecture — file touch list

Execution runs on a branch `rename/notecrux`. Verification is a clean `xcodebuild`. Merge is a single atomic merge commit to `main`.

### 3.1 Folder-level renames (via `git mv` to preserve history)

- `DeepPocket.ios.xcodeproj/` → `NoteCrux.xcodeproj/`.
- `DeepPocket.ios/` (source root) → `NoteCrux/`.
- No top-level `.xcworkspace` exists. The internal `project.xcworkspace/` inside the `.xcodeproj` directory moves automatically when its parent folder is renamed — no separate handling.

### 3.2 File-level renames (old path → new path, one-to-one)

- `DeepPocket.ios/DeepPocket_iosApp.swift` → `NoteCrux/NoteCruxApp.swift`.
- `DeepPocket.ios/DeepPocketLog.swift` → `NoteCrux/NoteCruxLog.swift`.
- `DeepPocket.ios/DeepPocket_ios.entitlements` → `NoteCrux/NoteCrux.entitlements`.
- `DeepPocket.ios/Services/DeepPocketShortcuts.swift` → `NoteCrux/Services/NoteCruxShortcuts.swift`.
- `DeepPocket.ios/Views/DeepPocketTheme.swift` → `NoteCrux/Views/NoteCruxTheme.swift`.
- `DeepPocket.ios/Intents/DeepPocketIntents.swift` → `NoteCrux/Intents/DeepPocketIntents.swift` (folder-only rename; filename stays). Of the four intent types inside (`StartRecordingIntent`, `TodaysAgendaIntent`, `AskDeepPocketIntent`, `LastMeetingDecisionsIntent`), three are brand-neutral; `AskDeepPocketIntent` is renamed in §3.3.
- Scheme XML: `DeepPocket.ios.xcodeproj/xcshareddata/xcschemes/DeepPocket.ios.xcscheme` → `NoteCrux.xcodeproj/xcshareddata/xcschemes/NoteCrux.xcscheme`.

### 3.3 Swift symbol renames (ripple to callers)

- `DeepPocketLog` → `NoteCruxLog` (enum; referenced in `AppRouter`, `FoundationModelClient`, `LocalInsightGenerator`, `MeetingAssistantEngine`, `CalendarImportService`, `MeetingExportService`, `DeepPocketIntents`, `InsightView`, `SettingsView`).
- `DeepPocket_iosApp` → `NoteCruxApp`.
- `DeepPocketShortcuts` → `NoteCruxShortcuts`.
- `DeepPocketTheme` → `NoteCruxTheme` (enum; referenced in `ContentView`, `AssistantView`, `AppLockView`, `VaultView`, `ProInsightsView`, and its own file).
- `DeepPocketBackup` → `NoteCruxBackup` (struct in `LocalBackupService.swift`; also update the constructor call on line 57 of that file).
- `AskDeepPocketIntent` → `AskNoteCruxIntent`. Also update every reference to this type: the `AppShortcut(intent: AskDeepPocketIntent(), ...)` registration inside `NoteCruxShortcuts` and any other navigation triggers that instantiate it. Missing a reference causes a runtime intent-type mismatch that AppIntents metadata generation won't catch.

### 3.4 `project.pbxproj` edits (one risky file)

- `PRODUCT_BUNDLE_IDENTIFIER` → `com.KasparWorks.NoteCrux` (both Debug and Release).
- `PRODUCT_NAME`, `INFOPLIST_KEY_CFBundleDisplayName`, `INFOPLIST_KEY_CFBundleName` → `NoteCrux`.
- Target display name `DeepPocket.ios` → `NoteCrux`.
- Filesystem-synchronized root path `DeepPocket.ios` → `NoteCrux`.
- `CODE_SIGN_ENTITLEMENTS` → `NoteCrux/NoteCrux.entitlements` (Debug and Release).
- Every `INFOPLIST_KEY_NSxxxUsageDescription` that mentions DeepPocket.
- Scheme-name reference.

### 3.5 Scheme XML edits

- In `NoteCrux.xcscheme`: every `BuildableName`, `BlueprintName`, and container reference updated to `NoteCrux`.

## 4. Execution order (phased for recovery)

Each phase commits independently. The project must build at the end of every phase except during mid-phase edits.

**Phase 0 — Branch & baseline.**
1. `git checkout -b rename/notecrux` from `main` at the current `HEAD` (commit `7a16442`).
2. Verify baseline `xcodebuild` still succeeds on the branch.

**Phase 1 — Non-breaking string edits.** Project builds after each commit.
1. Rename internal literal strings: logger subsystem, DispatchQueue labels. Commit.
2. Rename Swift symbols (`DeepPocketLog` → `NoteCruxLog`, `DeepPocketShortcuts` → `NoteCruxShortcuts`, `DeepPocket_iosApp` → `NoteCruxApp`, `AskDeepPocketIntent` → `AskNoteCruxIntent`). File names do not change yet. Commit.
3. User-visible string rewrites: `Text(...)`, Siri `shortTitle`, `AppIntent` `description` + `dialog(...)`. Commit.

**Phase 2 — Entitlements file rename.**
1. `git mv DeepPocket.ios/DeepPocket_ios.entitlements DeepPocket.ios/NoteCrux.entitlements`.
2. Update `CODE_SIGN_ENTITLEMENTS` in `project.pbxproj` (Debug and Release).
3. Build. Commit.

**Phase 3 — Swift file renames.**
1. `git mv` each renamed `.swift` file to its new name (still under the old root folder at this stage).
2. No `project.pbxproj` edit required (filesystem-synchronized group picks them up).
3. Build. Commit.

**Phase 4 — Root folder rename** (highest-risk single step).
1. `git mv DeepPocket.ios NoteCrux`.
2. Update every `DeepPocket.ios/` path reference in `project.pbxproj` to `NoteCrux/` — including the `CODE_SIGN_ENTITLEMENTS` value set in Phase 2.
3. **Open `NoteCrux.xcodeproj` in Xcode once** and visually verify file references resolve (no red filenames in the navigator) before running `xcodebuild`. Xcode's GUI catches broken references faster than the CLI.
4. Build. Commit.

**Phase 5 — Xcode project & bundle ID.**
1. `git mv DeepPocket.ios.xcodeproj NoteCrux.xcodeproj`.
2. `git mv NoteCrux.xcodeproj/xcshareddata/xcschemes/DeepPocket.ios.xcscheme NoteCrux.xcodeproj/xcshareddata/xcschemes/NoteCrux.xcscheme`.
3. In `project.pbxproj` and in the renamed scheme XML: apply the edits in §§3.4 and 3.5.
4. **Target / scheme linkage verification** (catches the classic "scheme builds nothing" issue):
   - Target named `NoteCrux`.
   - Scheme named `NoteCrux`.
   - Scheme `BuildableName` matches the renamed target's product name.
   - Auto-generated Info.plist path still resolves (verify via Xcode → target settings → Info).
5. Build: `xcodebuild -project NoteCrux.xcodeproj -scheme NoteCrux -destination 'generic/platform=iOS Simulator' build` → `** BUILD SUCCEEDED **`.
6. Commit.

**Phase 6 — Documentation renames.**
1. `git mv` the two superpowers docs + rewrite in-doc titles, and update any in-doc references to bundle IDs / logger subsystem / queue labels.
2. Commit.

**Phase 7 — Search-and-verify (mandatory before merge):**
1. `grep -rni "deeppocket" NoteCrux/` → expect zero hits.
2. `grep -rn "works\.kaspar\.deeppocket" .` → expect zero hits.
3. `grep -rn "DeepPocket_ios\.entitlements\|DeepPocket_iosApp\|DeepPocketShortcuts\|DeepPocketLog\|AskDeepPocketIntent" .` → expect zero hits outside historical docs.
4. `grep -rn "DeepPocket" NoteCrux.xcodeproj` → expect zero hits. `project.pbxproj` sometimes hides leftovers in display names, scheme references, or build settings that text grep surfaces but visual inspection misses.
5. Final clean build.
6. `grep "PRODUCT_BUNDLE_IDENTIFIER" NoteCrux.xcodeproj/project.pbxproj` → every entry should read `com.KasparWorks.NoteCrux`.

**Phase 8 — Merge & remote:**
1. Squash-merge to keep `main` clean as a single rebrand commit:
   ```
   git checkout main
   git merge --squash rename/notecrux
   git commit -m "rename: DeepPocket → NoteCrux (full rebrand)"
   ```
   Rationale: the per-phase commits were useful during execution for recovery, but `main` benefits from a single self-describing commit for the rebrand rather than eight phase commits plus a merge. The branch history is still discoverable via the branch ref before it's deleted.
2. `git remote set-url origin git@github.com:kaspar-works/NoteCrux_ios.git` (HTTPS acceptable).
3. `git push origin main` after confirming the GitHub repo rename has landed.
4. Delete the local branch: `git branch -D rename/notecrux`.

## 5. Risks & recovery

| Risk | Recovery |
|---|---|
| `project.pbxproj` left with a stale path after Phase 4 → build fails | `git diff HEAD~1 NoteCrux.xcodeproj/project.pbxproj`; grep for remaining `DeepPocket` in the pbxproj to find the miss |
| Xcode caches stale `DerivedData` producing weird link errors | `rm -rf ~/Library/Developer/Xcode/DerivedData/DeepPocket.ios-*` and `~/Library/Developer/Xcode/DerivedData/NoteCrux-*`; ⇧⌘K in Xcode |
| SourceKit shows phantom errors for hours | `xcodebuild` is the source of truth; wait for reindex or quit/relaunch Xcode |
| Scheme-XML BuildableName mismatch → "scheme could not be resolved" | Manage Schemes → delete + regenerate, OR fix `BuildableReference` entries manually |
| Entitlements path mismatch → code-sign error | `CODE_SIGN_ENTITLEMENTS` must match the post-rename filesystem path exactly |
| `git mv` produces two-rename diff instead of one clean move | Use a single `git mv src dst` per rename |
| Push fails because GitHub repo rename hasn't propagated | Verify in browser that the renamed repo URL loads before pushing |
| Device still has the old-bundle-ID DeepPocket install | New bundle ID means it installs as a separate app; manually delete the old DeepPocket install from device before testing NoteCrux |

**Per-phase rollback:** if any phase fails to build or produces unexpected diffs:
```
git reset --hard <last-green-commit>
```
where `<last-green-commit>` is the most recent commit that ended a green phase. Restart from the top of the phase that failed. The per-phase commit structure (Phases 0–7) means rollbacks are always to a known-good state.

## 6. Non-obvious decisions

- **Renaming the bundle ID invalidates any previously installed app and its associated sandbox storage.** The new bundle ID installs as an entirely separate app on any device. Pre-ship this is fine, but every local recording, UserDefaults entry, and keychain item saved under `com.KasparWorks.DeepPocket-ios` becomes invisible to NoteCrux. If you have test data on your device worth keeping, export it via the share sheet before the rename lands.
- **Git history keeps "DeepPocket" forever.** Deliberate — we don't rewrite history; the name was accurate at the time, and rewriting adds zero value while introducing risk.
- **Filesystem-synchronized groups keep `project.pbxproj` small.** Individual source files aren't listed, so Phases 1 and 3 don't touch the pbxproj at all. Only Phases 2, 4, and 5 do.
- **Phase 6 (docs rename) is genuinely optional.** The existing spec + plan served their purpose; renaming them is cosmetic. Kept in scope for consistency.
- **No behavior change.** Any diff during implementation that alters observable behavior is out of scope — stop and flag.
