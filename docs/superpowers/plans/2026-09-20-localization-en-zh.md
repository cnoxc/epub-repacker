# Dynamic Localization (English / Chinese) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement dynamic, real-time language switching between English (default) and Chinese (Simplified) for EPUB Repacker macOS app, featuring dual-entry controls (window top-right + menu bar) and persistent preference storage.

**Architecture:** A lightweight, type-safe core localization engine (`LocalizationManager` and `LocalizationKey`) in `EPUBRepackerCore`, defaulting to English, persisting in `UserDefaults`, broadcasting notifications upon change; `AppDelegate` and `MainViewController` listen for language changes and immediately update all UI text, menus, headers, and dialogs.

**Tech Stack:** Swift 6.4, AppKit, Foundation, zero external dependencies, macOS 13.0+.

## Global Constraints

- Target platform: macOS 13.0+ (Apple Silicon arm64).
- Zero third-party package dependencies.
- Default language MUST be English (`en`).
- Immediate live switching without requiring app restart.
- Maintain existing 10/10 tests passing in `TestRunner`.

---

### Task 1: Core Localization Engine & Exhaustive Dictionary (`LocalizationManager`)

**Files:**
- Create: `Sources/EPUBRepackerCore/Localization/AppLanguage.swift`
- Create: `Sources/EPUBRepackerCore/Localization/LocalizationKey.swift`
- Create: `Sources/EPUBRepackerCore/Localization/LocalizationManager.swift`
- Modify: `Sources/TestRunner/main.swift`

**Interfaces:**
- Consumes: `Foundation.UserDefaults`, `Foundation.NotificationCenter`
- Produces:
  - `AppLanguage: String, CaseIterable, Sendable` (`.english`, `.chinese`)
  - `LocalizationKey: String, CaseIterable, Sendable`
  - `LocalizationManager.shared.currentLanguage: AppLanguage`
  - `LocalizationManager.shared.setLanguage(_ lang: AppLanguage)`
  - `LocalizationManager.shared.string(_ key: LocalizationKey) -> String`
  - `LocalizationManager.shared.format(_ key: LocalizationKey, _ args: CVarArg...) -> String`
  - `Notification.Name.appLanguageDidChange`

- [ ] **Step 1: Write the failing tests in `Sources/TestRunner/main.swift`**

```swift
final class LocalizationTests {
    static func runAll() {
        testDefaultLanguageIsEnglish()
        testLanguageSwitchingAndPersistence()
        testCompleteDictionaryCoverage()
    }

    static func testDefaultLanguageIsEnglish() {
        print("▶ Running: LocalizationTests.testDefaultLanguageIsEnglish... ", terminator: "")
        UserDefaults.standard.removeObject(forKey: "selected_app_language")
        let manager = LocalizationManager(userDefaults: UserDefaults.standard)
        assert(manager.currentLanguage == .english, "Default language must be English")
        assert(manager.string(.windowTitle).contains("EPUB Repacker"), "Should return English string")
        print("✅ PASS")
    }

    static func testLanguageSwitchingAndPersistence() {
        print("▶ Running: LocalizationTests.testLanguageSwitchingAndPersistence... ", terminator: "")
        let testDefaults = UserDefaults(suiteName: "test_localization_\(UUID().uuidString)")!
        let manager = LocalizationManager(userDefaults: testDefaults)
        assert(manager.currentLanguage == .english)
        
        manager.setLanguage(.chinese)
        assert(manager.currentLanguage == .chinese)
        assert(manager.string(.dropTitle).contains("拖拽"))

        let restoredManager = LocalizationManager(userDefaults: testDefaults)
        assert(restoredManager.currentLanguage == .chinese, "Language preference must persist")
        print("✅ PASS")
    }

    static func testCompleteDictionaryCoverage() {
        print("▶ Running: LocalizationTests.testCompleteDictionaryCoverage... ", terminator: "")
        for lang in AppLanguage.allCases {
            for key in LocalizationKey.allCases {
                let text = LocalizationManager.lookup(key: key, language: lang)
                assert(!text.isEmpty, "Missing translation for \(key) in \(lang)")
            }
        }
        print("✅ PASS")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `CLANG_MODULE_CACHE_PATH="$(pwd)/.cache/clang" swift run --disable-sandbox --scratch-path .build/scratch TestRunner`
Expected: FAIL with "cannot find 'LocalizationManager' in scope"

- [ ] **Step 3: Implement `AppLanguage.swift`, `LocalizationKey.swift`, and `LocalizationManager.swift`**

Implement complete dictionary with every UI key translated in both English and Simplified Chinese.

- [ ] **Step 4: Run test to verify it passes**

Run: `CLANG_MODULE_CACHE_PATH="$(pwd)/.cache/clang" swift run --disable-sandbox --scratch-path .build/scratch TestRunner`
Expected: PASS (All tests including LocalizationTests pass)

- [ ] **Step 5: Commit**

```bash
git add Sources/EPUBRepackerCore/Localization/ Sources/TestRunner/main.swift
git commit -m "feat: add LocalizationManager with complete English and Chinese dictionaries"
```

---

### Task 2: Integrate UI Localization & Dynamic Live Switching in AppKit UI

**Files:**
- Modify: `Sources/EPUBRepackerApp/AppDelegate.swift`
- Modify: `Sources/EPUBRepackerApp/MainViewController.swift`

**Interfaces:**
- Consumes: `LocalizationManager.shared`, `Notification.Name.appLanguageDidChange`
- Produces:
  - Top-right window language selector `[English | 中文]` in `MainViewController`
  - `Language` menu in `AppDelegate.setupMenu()` with checkmarks
  - `updateLocalizedStrings()` method updating all labels, buttons, column titles, tooltips, and dialogs in real-time

- [ ] **Step 1: Update `AppDelegate.swift`**
  - Add `Language` menu to `setupMenu()`.
  - Add observer for `.appLanguageDidChange` to refresh menu and window title.
  - Implement `@objc private func selectLanguageFromMenu(_ sender: NSMenuItem)`.

- [ ] **Step 2: Update `MainViewController.swift`**
  - Add `languageSegmentedControl` in top-right or header bar.
  - Implement `updateLocalizedStrings()` covering:
    - Drop zone title, subtitle, browse button.
    - Export settings box: export title, segmented control labels, change folder button, open Books button, tooltip, and destination info label.
    - Table view column headers: `File Name`, `Status / Changes`, `Action`.
    - Table cell statuses and action button titles.
    - Bottom bar: clear button, start/cancel button, status label.
    - Alerts: Empty queue alert, Report dialog.
  - Observe `.appLanguageDidChange` and trigger `updateLocalizedStrings()`.

- [ ] **Step 3: Verify build and test compilation**

Run: `CLANG_MODULE_CACHE_PATH="$(pwd)/.cache/clang" swift build -c release --disable-sandbox --scratch-path .build/scratch --product EPUBRepackerApp`
Expected: Build complete with exit 0.

- [ ] **Step 4: Commit**

```bash
git add Sources/EPUBRepackerApp/
git commit -m "feat: implement dual-entry dynamic language switching in AppKit UI"
```

---

### Task 3: App Bundle Packaging, Signing & End-to-End Verification

**Files:**
- Execute: `scripts/build_app.sh`
- Verify: `dist/EPUBRepacker.app`

- [ ] **Step 1: Package and sign macOS app**

Run: `./scripts/build_app.sh`
Expected: Exit 0, bundle generated at `dist/EPUBRepacker.app`.

- [ ] **Step 2: Verify bundle integrity and signature**

Run: `codesign --verify --verbose dist/EPUBRepacker.app`
Expected: `valid on disk`, `satisfies its Designated Requirement`.

- [ ] **Step 3: Run full automated test suite**

Run: `CLANG_MODULE_CACHE_PATH="$(pwd)/.cache/clang" swift run --disable-sandbox --scratch-path .build/scratch TestRunner`
Expected: All tests pass.

- [ ] **Step 4: Commit and update walkthrough**

```bash
git commit -m "chore: release EPUBRepacker with dynamic English/Chinese localization"
```
