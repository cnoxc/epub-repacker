<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="EPUB Repacker Icon" />
</p>

<h1 align="center">EPUB Repacker</h1>

<p align="center">
  <strong>A lightweight, native macOS utility for standardizing, repairing, and repacking EPUB publications with direct Apple Books iCloud integration.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT" /></a>
  <img src="https://img.shields.io/badge/Platform-macOS%2013.0+-orange.svg" alt="Platform: macOS 13+" />
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-purple.svg" alt="Apple Silicon" />
  <img src="https://img.shields.io/badge/Swift-5.9%20%7C%206.4-red.svg" alt="Swift Version" />
  <img src="https://img.shields.io/badge/Dependencies-Zero-green.svg" alt="Zero Dependencies" />
</p>

<p align="center">
  <a href="README.md"><b>English</b></a> | <a href="README_ZH.md"><b>简体中文</b></a>
</p>

---

## 📖 Overview

When editing or decompiling `.epub` eBooks on macOS, hidden file system artifacts (`.DS_Store`, `__MACOSX`), missing entries in `content.opf`, or improper zip compression often cause e-readers (notably **Apple Books** on Mac, iPhone, and iPad) to reject or fail to open the file.

According to the official **IDPF / W3C EPUB specification**, the very first file in an EPUB archive must be an uncompressed `mimetype` file with zero extra fields. Standard compression tools (`zip`, Finder Archive Utility) do not respect this rule.

**EPUB Repacker** is a modern, fast, and native macOS desktop app designed to solve this with a single drag-and-drop:
- Automatically fixes uncompressed `mimetype` headers.
- Self-heals broken or missing `META-INF/container.xml`.
- Scans and synchronizes manifest resources with spine items in `content.opf`.
- Cleans up OS metadata junk.
- Directly exports repacked books to your **Apple Books iCloud synchronization directory**.

---

## ✨ Key Features

- **Strict IDPF / W3C Specification Compliance**:
  - Archive entry 0 is guaranteed to be `mimetype` using Compression Method 0 (`STORED`), without extra fields, containing `application/epub+zip`.
  - All chapter content, stylesheets, and media are compressed using standard `DEFLATE`.
- **Automated Container & Manifest Repair**:
  - Automatically reconstructs missing `META-INF/container.xml` pointing to the actual `.opf` rootfile.
  - Recursively discovers XHTML, CSS, PNG, JPEG, SVG, WebP, and fonts; registers missing items with correct MIME types into `manifest`.
  - Cleans up dangling dead links in `manifest`.
- **macOS System Artifact Stripping**:
  - Completely strips `.DS_Store`, `__MACOSX`, and Windows `Thumbs.db`.
- **Apple Books iCloud Direct Integration**:
  - Includes a built-in shortcut to send repacked EPUBs straight to `~/Library/Mobile Documents/iCloud~com~apple~iBooks/Documents/`.
  - One-click shortcut button (and `Cmd + B`) to open the iCloud Books directory directly in Finder.
- **Dynamic Multilingual Support (English & 简体中文)**:
  - Default language is **English**.
  - Live, instant language switching without restarting the application via either the main window top-right selector or the system Menu Bar.
  - Automatically remembers your language preference across restarts.
- **Pure Native & Zero Dependencies**:
  - Built with pure Swift and AppKit.
  - Zero third-party dependencies, minimal memory footprint (<20MB), and instantaneous launch time.

---

## 🖥️ User Interface & Workflow

```
+-----------------------------------------------------------------------+
|  EPUB Repacker                       [ 📚 Open Books Folder ] [EN|中文]|
+-----------------------------------------------------------------------+
|                                                                       |
|      📦 Drag & drop EPUB files or unpacked folders here               |
|      Automatically repairs mimetype, container, and manifest          |
|                       [ Select Files / Folders... ]                   |
|                                                                       |
+-----------------------------------------------------------------------+
|  Export Destination: (o) Same Folder  ( ) Apple Books  ( ) Custom     |
|  Current Destination: ~/Library/Mobile Documents/.../Documents/       |
+-----------------------------------------------------------------------+
|  File Name              Status / Changes                    Action    |
|  -------------------------------------------------------------------  |
|  book1.epub             ✅ Done (-14.2 KB)          [Report] [Finder] |
|  book2_extracted        ✅ Done (+2 items added)    [Report] [Finder] |
+-----------------------------------------------------------------------+
|  [ Clear List ]                  Progress: 2/2       [ Repack All ]   |
+-----------------------------------------------------------------------+
```

### Typical Usage:
1. Drag and drop one or multiple `.epub` files (or uncompressed book directories) into the app window.
2. Choose your export destination (Original Folder, Apple Books iCloud, or Custom Folder).
3. Click **"Repack All"**.
4. View the detailed repair report or click **"Finder"** to immediately locate the repacked `.epub`!

---

## 📥 Installation

### Option 1: Download Pre-built Release (Recommended)
1. Go to the [Releases](https://github.com) page.
2. Download `EPUBRepacker-macOS-v1.0.0.zip`.
3. Extract the archive and drag `EPUBRepacker.app` to your `/Applications` folder.
4. Double-click to run!

> **Note on Gatekeeper**: Because this open-source build is ad-hoc signed, macOS may show a prompt on first run. If prompted, right-click the app and choose **Open**, or go to **System Settings > Privacy & Security** and click **Open Anyway**.

---

### Option 2: Build from Source

#### Prerequisites:
- macOS 13.0+
- Swift 5.9+ / Xcode Command Line Tools (`xcode-select --install`)

```bash
# 1. Clone repository
git clone https://github.com/<your-username>/epub-repacker.git
cd epub-repacker

# 2. Run automated test suite (11 test suites)
CLANG_MODULE_CACHE_PATH="$(pwd)/.cache/clang" swift run --disable-sandbox --scratch-path .build/scratch TestRunner

# 3. Build standalone .app bundle
./scripts/build_app.sh

# 4. Open the built application
open dist/EPUBRepacker.app
```

---

## 🏗️ Architecture

```
epub-repacker/
├── Package.swift                             # SwiftPM configuration
├── Sources/
│   ├── EPUBRepackerCore/                     # Headless engine & models
│   │   ├── Localization/                     # LocalizationManager, AppLanguage, LocalizationKey
│   │   ├── Models/                           # OutputOption, RepairReport, RepackTaskItem
│   │   ├── Services/                         # EPUBPackager, EPUBExtractor, EPUBRepairer
│   │   └── ViewModel/                        # RepackViewModel (observable state)
│   ├── EPUBRepackerApp/                      # Native AppKit GUI application
│   │   ├── AppDelegate.swift                 # Application lifecycle & Menu Bar setup
│   │   ├── MainViewController.swift          # Main UI view controller
│   │   └── Resources/AppIcon.icns            # Multi-resolution macOS AppIcon
│   └── TestRunner/                           # Verification & automated test suite
├── scripts/
│   ├── build_app.sh                          # App bundle build & signing script
│   ├── generate_app_icon.py                  # High-resolution icns generation script
│   └── package_release.sh                    # Release packager (.zip with SHA256)
└── assets/                                   # Project badges and icon assets
```

---

## 🧪 Testing

The repository includes a standalone test harness verifying core functionality without requiring third-party testing frameworks:

```bash
CLANG_MODULE_CACHE_PATH="$(pwd)/.cache/clang" swift run --disable-sandbox --scratch-path .build/scratch TestRunner
```

**Covered Test Scenarios:**
- Core data models & size difference formatting
- `EPUBPackager` uncompressed `mimetype` byte verification
- Archive magic header rejection on corrupt files
- `EPUBRepairer` automated self-healing on broken EPUBs
- Batch asynchronous queue concurrency
- End-to-end extraction, repair, repacking, and uncompressed byte inspection
- `LocalizationManager` default English fallback, `UserDefaults` persistence, and exhaustive dictionary coverage

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.
