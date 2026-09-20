# EPUB Repacker for macOS - Technical Design Specification

- **Author**: Antigravity Assistant
- **Date**: 2026-09-20
- **Status**: Approved
- **Platform**: macOS (Apple Silicon arm64 / macOS 13+)
- **Technology Stack**: Swift 6.4, SwiftUI, AppKit, System Compression / Zip APIs

---

## 1. Overview & Goals

EPUB Repacker is a native, lightweight macOS desktop application designed to inspect, repair, clean, and repackage EPUB electronic book files into standard-compliant EPUB containers.

### Core Objectives
1. **Container & Spec Normalization**:
   - Strictly guarantee that `mimetype` is the first file entry in the ZIP archive, stored uncompressed (Compression Method 0: STORED, no extra fields), containing strictly `application/epub+zip`.
   - Ensure valid `META-INF/container.xml` pointing to the primary `.opf` rootfile path.
   - Reconstruct and synchronize the OPF `<manifest>` with physical files on disk:
     - Automatically register unmanifested content files (XHTML, images, fonts, audio, video, CSS) with valid MIME types and generated IDs.
     - Remove dead / missing entries from the manifest.
     - Verify and sanitize `<spine>` references.
   - Strip OS junk files (such as `.DS_Store`, `__MACOSX/`, `Thumbs.db`).
2. **Incremental Batch Processing**:
   - Single-file repair engine validated with 100% integrity first.
   - Batch drag-and-drop processing queue with concurrency, progress tracking, and per-item status.
3. **Zero-Dependency Native macOS Experience**:
   - Built with Swift 6 and SwiftUI.
   - Self-contained `.app` bundle runnable directly on macOS without Python, Node, or third-party framework runtime requirements.
   - Clean native UI supporting dark/light mode, file drag-and-drop, and detailed repair logs.

---

## 2. Architecture & Components

```
┌─────────────────────────────────────────────────────────┐
│                      SwiftUI View                       │
│   [DropZone / FilePicker]  [Batch Queue]  [Log Sheet]   │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│                    ViewModel Layer                      │
│   - Batch task queue management                         │
│   - Concurrency control via Swift async/await           │
│   - Item states: pending, processing, success, failed   │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│                   Core EPUB Engine                      │
│                                                         │
│  ┌─────────────────┐  ┌────────────────┐  ┌──────────┐  │
│  │  EPUBExtractor  │─►│  EPUBRepairer  │─►│Packager  │  │
│  │ (Unzip sandbox) │  │(Manifest/OPF)  │  │(Spec Zip)│  │
│  └─────────────────┘  └────────────────┘  └──────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 2.1 Component Specifications

#### 1. `EPUBExtractor`
- **Responsibility**: Takes an `.epub` file URL or a pre-unpacked book folder URL.
- **Workflow**:
  - Creates a dedicated staging sandbox under `NSTemporaryDirectory()/EPUBRepacker/<UUID>/`.
  - Unzips the source `.epub` archive cleanly into this staging directory.

#### 2. `EPUBRepairer`
- **Responsibility**: Scans, validates, and fixes book metadata, container files, and manifests.
- **Checks & Actions**:
  - **MimeType**: Creates or normalizes root `mimetype` file with content `application/epub+zip` (stripped of newlines/BOM/extra whitespace).
  - **Container XML**:
    - Checks for `META-INF/container.xml`.
    - If missing or pointing to a non-existent file, recursively locates `.opf` package files and builds a standard XML container referencing the actual OPF rootfile path.
  - **OPF & Manifest Synchronization**:
    - Locates the OPF file and parses its XML contents.
    - Scans all files in the OPF content tree.
    - Automatically maps file extensions to correct MIME types (`.xhtml`, `.html`, `.css`, `.jpg`, `.jpeg`, `.png`, `.webp`, `.svg`, `.otf`, `.ttf`, `.woff`, `.woff2`, `.ncx`, `.smil`).
    - Appends missing resources to `<manifest>`.
    - Prunes manifest items whose target files do not exist on disk.
    - Validates that `<spine>` item references point to valid manifest items.
  - **Sanitization**:
    - Deletes `.DS_Store`, `__MACOSX`, `Thumbs.db`, `.git*` files from staging.
- **Outputs**: Generates a structured `RepairReport` detailing changes made.

#### 3. `EPUBPackager`
- **Responsibility**: Creates the final `.epub` ZIP archive according to IDPF / W3C specifications.
- **Rules**:
  1. Entry 0 MUST be `mimetype` with compression level 0 (STORED) and without extra header fields.
  2. All remaining files (`META-INF/container.xml`, content files, OPF, etc.) are archived with Deflate compression.
  3. Writes to the target destination path (defaults to `<original_name>_repacked.epub`).
  4. Runs byte-level verification on the resulting `.epub` to ensure the magic bytes and `mimetype` signature match the specification.

#### 4. `RepackViewModel` & UI
- **Observable Properties**:
  - `items: [RepackTaskItem]`
  - `overallProgress: Double`
  - `isProcessing: Bool`
  - `outputOption: OutputOption` (`.sameDirectoryWithSuffix` or `.customDirectory`)
- **UI Components**:
  - `DropZoneView`: Drag & drop target with visual feedback.
  - `TaskRowView`: Status indicator icon, file size before/after, action buttons (Reveal in Finder, View Report).
  - `ReportDetailSheet`: Displays detailed change log for selected item.

---

## 3. Data Flow & State Machine

```
   [User Drops Files]
           │
           ▼
   Create [RepackTaskItem] (status: .pending)
           │
           ▼
   User clicks [Start Repack] (or auto-start option)
           │
           ▼
    ┌───────────────────────────┐
    │ Task processing loop      │
    │ (async TaskGroup)         │
    └──────────────┬────────────┘
                   │
         ┌─────────┴─────────┐
         ▼                   ▼
   [Success Path]      [Failure Path]
   - Status: .success  - Status: .failed(reason)
   - Size recorded     - Non-blocking to batch
   - Report logged     - Error recorded in log
```

---

## 4. Error Handling & Edge Cases

| Scenario | Handling Strategy |
|----------|-------------------|
| Corrupt / invalid ZIP file | Marks specific item as `.failed("无效的 ZIP 归档")`, continues processing queue. |
| Missing OPF file entirely | Scans for any HTML/XHTML content. If content exists, constructs minimal OPF package; otherwise reports missing OPF. |
| Non-standard characters in file names | Safely handles URL encoding / decoding and UTF-8 path resolutions. |
| Target file already exists | Automatically appends sequence counter (e.g. `_repacked (1).epub`) or updates existing backup safely. |
| Permission denied on output dir | Prompts user to choose an alternative output directory. |

---

## 5. Verification Plan

### Automated Unit / Integration Tests
1. **EPUB Packaging Spec Test**:
   - Generate an EPUB package and assert that the first 58 bytes strictly match:
     `PK\x03\x04` header, zero compression flag, filename length 8 (`mimetype`), and body `application/epub+zip`.
2. **Missing Mimetype & Container Repair Test**:
   - Provide broken input missing `mimetype` and `container.xml`.
   - Run repairer and verify standard files are reconstructed.
3. **Manifest Sync Test**:
   - Add extra unlisted images to the content directory.
   - Delete a file referenced in manifest.
   - Run repairer and assert manifest adds the extra image and removes the orphan reference.
4. **Batch Processing Test**:
   - Process multiple EPUB files concurrently and assert all succeed without interference.

### Manual App Verification
- Build and launch the `EPUBRepacker.app` bundle.
- Drag & drop sample EPUB files onto the window.
- Verify status changes, inspect repair reports, and open the repacked EPUB in Apple Books (macOS Books.app) to confirm proper rendering.
