# Contributing to EPUB Repacker

Thank you for your interest in contributing to **EPUB Repacker**! We welcome bug fixes, documentation improvements, translations, and architectural enhancements.

---

## 🛠 Prerequisites & Environment

- **macOS**: 13.0 or newer (Optimized for Apple Silicon `arm64`).
- **Toolchain**: Swift 5.9 or newer (Xcode Command Line Tools).
- **Dependencies**: **Zero third-party dependencies**. All features use Apple's native frameworks (`Foundation`, `AppKit`, `UniformTypeIdentifiers`).

---

## 🚀 Building & Testing Locally

1. **Clone the repository:**
   ```bash
   git clone https://github.com/<your-username>/epub-repacker.git
   cd epub-repacker
   ```

2. **Run the test suite:**
   ```bash
   CLANG_MODULE_CACHE_PATH="$(pwd)/.cache/clang" swift run --disable-sandbox --scratch-path .build/scratch TestRunner
   ```

3. **Build the macOS `.app` bundle:**
   ```bash
   ./scripts/build_app.sh
   ```
   The built application will be output to `dist/EPUBRepacker.app`.

4. **Package a release archive:**
   ```bash
   ./scripts/package_release.sh
   ```

---

## 📐 Architecture Overview

- **`EPUBRepackerCore/`**: Pure business logic and EPUB manipulation.
  - `Services/EPUBPackager.swift`: IDPF/W3C spec-compliant packaging (mimetype stored uncompressed, remaining assets deflated).
  - `Services/EPUBExtractor.swift`: Safe archive extraction and file system normalization.
  - `Services/EPUBRepairer.swift`: Automated self-healing for container XML, manifest items, and junk cleanup.
  - `Localization/`: Core localization engine (`LocalizationManager`, `AppLanguage`, `LocalizationKey`).
- **`EPUBRepackerApp/`**: Native AppKit desktop user interface.
  - `MainViewController.swift`: Drag-and-drop zone, export configuration, queue table, and real-time live language updates.
  - `AppDelegate.swift`: Window management, system menu bar, and ad-hoc icon loading.
- **`TestRunner/`**: Standalone automated test harness covering all models, services, and localization dictionaries.

---

## 📝 Pull Request Guidelines

1. Ensure all 11 test suites pass with zero failures before submitting.
2. If introducing new user-facing strings, add corresponding keys and translations for both English and Simplified Chinese in `Sources/EPUBRepackerCore/Localization/LocalizationKey.swift`.
3. Follow idiomatic Swift style guidelines and maintain clean git commit messages (e.g., `feat: ...`, `fix: ...`, `docs: ...`).
