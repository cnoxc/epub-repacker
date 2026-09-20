import AppKit
import UniformTypeIdentifiers
import EPUBRepackerCore

final class DropZoneView: NSBox {
    var onFilesDropped: (([URL]) -> Void)?
    private var isHighlighted = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        boxType = .custom
        cornerRadius = 10
        borderWidth = 2
        borderColor = NSColor.separatorColor
        fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isHighlighted = true
        borderColor = NSColor.controlAccentColor
        needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHighlighted = false
        borderColor = NSColor.separatorColor
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHighlighted = false
        borderColor = NSColor.separatorColor
        needsDisplay = true

        guard let pasteboard = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        onFilesDropped?(pasteboard)
        return true
    }
}

final class MainViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let viewModel = RepackViewModel()
    private let tableView = NSTableView()
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let startButton = NSButton()
    private let clearButton = NSButton()

    // Language selector
    private let languageSegmentedControl = NSSegmentedControl()

    // Drop zone views
    private let dropTitleLabel = NSTextField(labelWithString: "")
    private let dropSubtitleLabel = NSTextField(labelWithString: "")
    private let browseButton = NSButton()

    // Output destination & shortcut controls
    private let exportTitleLabel = NSTextField(labelWithString: "")
    private let outputSegmentedControl = NSSegmentedControl()
    private let changeFolderButton = NSButton()
    private let currentDestLabel = NSTextField(labelWithString: "")
    private let openBooksButton = NSButton()

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 780, height: 600))
        self.view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateLocalizedStrings()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageDidChange(_:)),
            name: .appLanguageDidChange,
            object: nil
        )
    }

    private func setupUI() {
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])

        // 0. Top Bar (Language Selector)
        let topBarStack = NSStackView()
        topBarStack.orientation = .horizontal
        topBarStack.spacing = 8
        topBarStack.alignment = .centerY
        topBarStack.translatesAutoresizingMaskIntoConstraints = false

        languageSegmentedControl.segmentCount = 2
        languageSegmentedControl.setLabel("English", forSegment: 0)
        languageSegmentedControl.setLabel("中文", forSegment: 1)
        languageSegmentedControl.trackingMode = .selectOne
        languageSegmentedControl.target = self
        languageSegmentedControl.action = #selector(languageSegmentChanged(_:))
        languageSegmentedControl.setContentHuggingPriority(.required, for: .horizontal)

        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        topBarStack.addArrangedSubview(topSpacer)
        topBarStack.addArrangedSubview(languageSegmentedControl)

        mainStack.addArrangedSubview(topBarStack)

        // 1. Drop Zone
        let dropZone = DropZoneView()
        dropZone.translatesAutoresizingMaskIntoConstraints = false
        dropZone.heightAnchor.constraint(equalToConstant: 120).isActive = true
        dropZone.onFilesDropped = { [weak self] urls in
            self?.handleAddedURLs(urls)
        }

        let dropStack = NSStackView()
        dropStack.orientation = .vertical
        dropStack.spacing = 6
        dropStack.alignment = .centerX
        dropStack.translatesAutoresizingMaskIntoConstraints = false
        dropZone.addSubview(dropStack)

        NSLayoutConstraint.activate([
            dropStack.centerXAnchor.constraint(equalTo: dropZone.centerXAnchor),
            dropStack.centerYAnchor.constraint(equalTo: dropZone.centerYAnchor)
        ])

        dropTitleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        dropSubtitleLabel.font = NSFont.systemFont(ofSize: 12)
        dropSubtitleLabel.textColor = .secondaryLabelColor

        browseButton.bezelStyle = .rounded
        browseButton.target = self
        browseButton.action = #selector(browseFiles)

        dropStack.addArrangedSubview(dropTitleLabel)
        dropStack.addArrangedSubview(dropSubtitleLabel)
        dropStack.addArrangedSubview(browseButton)

        mainStack.addArrangedSubview(dropZone)

        // 2. Output Settings & Books Shortcut Bar
        let settingsBox = NSBox()
        settingsBox.boxType = .custom
        settingsBox.cornerRadius = 8
        settingsBox.borderWidth = 1
        settingsBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.6)
        settingsBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.3)
        settingsBox.translatesAutoresizingMaskIntoConstraints = false

        let settingsStack = NSStackView()
        settingsStack.orientation = .vertical
        settingsStack.spacing = 8
        settingsStack.translatesAutoresizingMaskIntoConstraints = false
        settingsBox.addSubview(settingsStack)

        NSLayoutConstraint.activate([
            settingsStack.topAnchor.constraint(equalTo: settingsBox.topAnchor, constant: 10),
            settingsStack.leadingAnchor.constraint(equalTo: settingsBox.leadingAnchor, constant: 12),
            settingsStack.trailingAnchor.constraint(equalTo: settingsBox.trailingAnchor, constant: -12),
            settingsStack.bottomAnchor.constraint(equalTo: settingsBox.bottomAnchor, constant: -10)
        ])

        let row1 = NSStackView()
        row1.orientation = .horizontal
        row1.spacing = 10
        row1.alignment = .centerY

        exportTitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        outputSegmentedControl.segmentCount = 3
        outputSegmentedControl.selectedSegment = 0
        outputSegmentedControl.target = self
        outputSegmentedControl.action = #selector(outputOptionChanged(_:))

        changeFolderButton.target = self
        changeFolderButton.action = #selector(chooseCustomFolder)
        changeFolderButton.bezelStyle = .rounded
        changeFolderButton.font = NSFont.systemFont(ofSize: 11)
        changeFolderButton.isEnabled = false

        openBooksButton.bezelStyle = .rounded
        openBooksButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        openBooksButton.target = self
        openBooksButton.action = #selector(openBooksFolder)

        let row1Spacer = NSView()
        row1Spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row1.addArrangedSubview(exportTitleLabel)
        row1.addArrangedSubview(outputSegmentedControl)
        row1.addArrangedSubview(changeFolderButton)
        row1.addArrangedSubview(row1Spacer)
        row1.addArrangedSubview(openBooksButton)

        currentDestLabel.font = NSFont.systemFont(ofSize: 11)
        currentDestLabel.textColor = .secondaryLabelColor
        currentDestLabel.lineBreakMode = .byTruncatingMiddle

        settingsStack.addArrangedSubview(row1)
        settingsStack.addArrangedSubview(currentDestLabel)

        mainStack.addArrangedSubview(settingsBox)

        // 3. Table View for Queue
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 36
        tableView.usesAlternatingRowBackgroundColors = true

        let colFile = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileCol"))
        colFile.width = 320

        let colStatus = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("StatusCol"))
        colStatus.width = 200

        let colAction = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ActionCol"))
        colAction.width = 160

        tableView.addTableColumn(colFile)
        tableView.addTableColumn(colStatus)
        tableView.addTableColumn(colAction)

        scrollView.documentView = tableView
        mainStack.addArrangedSubview(scrollView)

        // 4. Bottom Bar
        let bottomStack = NSStackView()
        bottomStack.orientation = .horizontal
        bottomStack.spacing = 12
        bottomStack.alignment = .centerY
        bottomStack.translatesAutoresizingMaskIntoConstraints = false

        clearButton.target = self
        clearButton.action = #selector(clearQueue)
        clearButton.bezelStyle = .rounded

        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.widthAnchor.constraint(equalToConstant: 140).isActive = true
        progressIndicator.isHidden = true

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor

        startButton.bezelStyle = .rounded
        startButton.target = self
        startButton.action = #selector(startProcessing)
        startButton.keyEquivalent = "\r"

        let bottomSpacer = NSView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        bottomStack.addArrangedSubview(clearButton)
        bottomStack.addArrangedSubview(bottomSpacer)
        bottomStack.addArrangedSubview(progressIndicator)
        bottomStack.addArrangedSubview(statusLabel)
        bottomStack.addArrangedSubview(startButton)

        mainStack.addArrangedSubview(bottomStack)
    }

    private func updateLocalizedStrings() {
        languageSegmentedControl.selectedSegment = (LocalizationManager.shared.currentLanguage == .english ? 0 : 1)

        dropTitleLabel.stringValue = LocalizationManager.shared.string(.dropTitle)
        dropSubtitleLabel.stringValue = LocalizationManager.shared.string(.dropSubtitle)
        browseButton.title = LocalizationManager.shared.string(.browseButton)

        exportTitleLabel.stringValue = LocalizationManager.shared.string(.exportTitle)
        outputSegmentedControl.setLabel(LocalizationManager.shared.string(.exportSameDir), forSegment: 0)
        outputSegmentedControl.setLabel(LocalizationManager.shared.string(.exportAppleBooks), forSegment: 1)
        outputSegmentedControl.setLabel(LocalizationManager.shared.string(.exportCustomDir), forSegment: 2)
        changeFolderButton.title = LocalizationManager.shared.string(.changeFolderButton)
        openBooksButton.title = LocalizationManager.shared.string(.openBooksButton)
        openBooksButton.toolTip = LocalizationManager.shared.string(.openBooksTooltip)
        updateDestLabel()

        if let col = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("FileCol")) {
            col.title = LocalizationManager.shared.string(.colFileName)
        }
        if let col = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("StatusCol")) {
            col.title = LocalizationManager.shared.string(.colStatus)
        }
        if let col = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("ActionCol")) {
            col.title = LocalizationManager.shared.string(.colAction)
        }
        tableView.reloadData()

        clearButton.title = LocalizationManager.shared.string(.btnClearQueue)
        if viewModel.isProcessing {
            startButton.title = LocalizationManager.shared.string(.btnCancel)
            statusLabel.stringValue = LocalizationManager.shared.string(.statusProcessing)
        } else {
            startButton.title = LocalizationManager.shared.string(.btnStartRepack)
            if viewModel.items.isEmpty {
                statusLabel.stringValue = LocalizationManager.shared.string(.statusReady)
            } else if viewModel.items.allSatisfy({ if case .success = $0.status { return true }; return false }) {
                statusLabel.stringValue = LocalizationManager.shared.string(.statusCompleted)
            } else {
                statusLabel.stringValue = LocalizationManager.shared.format(.statusItemsAdded, viewModel.items.count)
            }
        }
    }

    @objc private func languageSegmentChanged(_ sender: NSSegmentedControl) {
        let targetLang: AppLanguage = (sender.selectedSegment == 0) ? .english : .chinese
        if LocalizationManager.shared.currentLanguage != targetLang {
            LocalizationManager.shared.setLanguage(targetLang)
        }
    }

    @objc private func handleLanguageDidChange(_ notification: Notification) {
        if Thread.isMainThread {
            self.updateLocalizedStrings()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateLocalizedStrings()
            }
        }
    }

    @objc private func outputOptionChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0:
            viewModel.outputOption = .sameDirectoryWithSuffix
            changeFolderButton.isEnabled = false
        case 1:
            viewModel.outputOption = .appleBooksICloud
            changeFolderButton.isEnabled = false
        case 2:
            changeFolderButton.isEnabled = true
            if viewModel.customOutputFolder == nil {
                chooseCustomFolder()
                return
            } else {
                viewModel.outputOption = .customDirectory(viewModel.customOutputFolder!)
            }
        default:
            break
        }
        updateDestLabel()
    }

    @objc private func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = LocalizationManager.shared.string(.chooseFolderPrompt)

        if panel.runModal() == .OK, let selectedURL = panel.url {
            viewModel.customOutputFolder = selectedURL
            viewModel.outputOption = .customDirectory(selectedURL)
            outputSegmentedControl.selectedSegment = 2
            changeFolderButton.isEnabled = true
        } else if viewModel.customOutputFolder == nil {
            outputSegmentedControl.selectedSegment = 0
            viewModel.outputOption = .sameDirectoryWithSuffix
            changeFolderButton.isEnabled = false
        }
        updateDestLabel()
    }

    private func updateDestLabel() {
        switch viewModel.outputOption {
        case .sameDirectoryWithSuffix:
            currentDestLabel.stringValue = LocalizationManager.shared.string(.destCurrentSameDir)
        case .appleBooksICloud:
            currentDestLabel.stringValue = LocalizationManager.shared.format(.destCurrentAppleBooks, OutputOption.appleBooksDocumentsURL.path)
        case .customDirectory(let url):
            currentDestLabel.stringValue = LocalizationManager.shared.format(.destCurrentCustom, url.path)
        }
    }

    @objc private func openBooksFolder() {
        let success = OutputOption.openAppleBooksDocumentsInFinder()
        if success {
            statusLabel.stringValue = LocalizationManager.shared.string(.booksOpenedInFinder)
        } else {
            statusLabel.stringValue = LocalizationManager.shared.string(.booksOpenFailed)
        }
    }

    @objc private func browseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data, .folder]
        if panel.runModal() == .OK {
            handleAddedURLs(panel.urls)
        }
    }

    private func handleAddedURLs(_ urls: [URL]) {
        viewModel.addItems(urls: urls)
        tableView.reloadData()
        statusLabel.stringValue = LocalizationManager.shared.format(.statusItemsAdded, viewModel.items.count)
    }

    @objc private func clearQueue() {
        guard !viewModel.isProcessing else { return }
        viewModel.clearList()
        tableView.reloadData()
        statusLabel.stringValue = LocalizationManager.shared.string(.statusListCleared)
        progressIndicator.isHidden = true
    }

    @objc private func startProcessing() {
        guard !viewModel.isProcessing else {
            viewModel.cancelAll()
            viewModel.isProcessing = false
            startButton.title = LocalizationManager.shared.string(.btnStartRepack)
            clearButton.isEnabled = true
            return
        }

        guard !viewModel.items.isEmpty else {
            let alert = NSAlert()
            alert.messageText = LocalizationManager.shared.string(.alertEmptyTitle)
            alert.informativeText = LocalizationManager.shared.string(.alertEmptyMessage)
            alert.addButton(withTitle: LocalizationManager.shared.string(.alertBtnOK))
            alert.runModal()
            return
        }

        viewModel.isProcessing = true
        startButton.title = LocalizationManager.shared.string(.btnCancel)
        clearButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.doubleValue = 0

        Task { @MainActor in
            defer {
                self.viewModel.isProcessing = false
                self.startButton.title = LocalizationManager.shared.string(.btnStartRepack)
                self.clearButton.isEnabled = true
            }

            statusLabel.stringValue = LocalizationManager.shared.string(.statusProcessing)
            for (index, item) in viewModel.items.enumerated() {
                if !self.viewModel.isProcessing { break }
                if case .success = item.status { continue }
                item.status = .processing(0.1)
                tableView.reloadData()

                let source = item.sourceURL
                let opt = viewModel.outputOption
                do {
                    let report = try await Task.detached(priority: .userInitiated) {
                        try EPUBRepairer.repairAndRepack(sourceURL: source, outputDir: nil, option: opt)
                    }.value
                    item.report = report
                    item.status = .success(report)
                } catch {
                    item.status = .failed(error.localizedDescription)
                }

                self.progressIndicator.doubleValue = Double(index + 1) / Double(viewModel.items.count) * 100
                self.statusLabel.stringValue = LocalizationManager.shared.format(.statusProgress, index + 1, viewModel.items.count)
                self.tableView.reloadData()
            }

            if self.viewModel.isProcessing {
                self.statusLabel.stringValue = LocalizationManager.shared.string(.statusCompleted)
                self.progressIndicator.doubleValue = 100
            }
        }
    }

    // MARK: - NSTableViewDataSource & Delegate
    func numberOfRows(in tableView: NSTableView) -> Int {
        return viewModel.items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < viewModel.items.count else { return nil }
        let item = viewModel.items[row]
        let colIdentifier = tableColumn?.identifier.rawValue

        if colIdentifier == "FileCol" {
            let cell = NSTextField(labelWithString: item.fileName)
            cell.font = NSFont.systemFont(ofSize: 13)
            return cell
        } else if colIdentifier == "StatusCol" {
            let cell = NSTextField()
            cell.isBordered = false
            cell.drawsBackground = false
            cell.isEditable = false
            cell.font = NSFont.systemFont(ofSize: 12)

            switch item.status {
            case .pending:
                cell.stringValue = LocalizationManager.shared.string(.itemStatusPending)
                cell.textColor = .secondaryLabelColor
            case .processing:
                cell.stringValue = LocalizationManager.shared.string(.itemStatusProcessing)
                cell.textColor = .systemBlue
            case .success(let report):
                cell.stringValue = LocalizationManager.shared.format(.itemStatusSuccess, report.sizeDifferenceFormatted)
                cell.textColor = .systemGreen
            case .failed(let err):
                cell.stringValue = LocalizationManager.shared.format(.itemStatusFailed, err)
                cell.textColor = .systemRed
            }
            return cell
        } else if colIdentifier == "ActionCol" {
            let cellStack = NSStackView()
            cellStack.orientation = .horizontal
            cellStack.spacing = 8

            if case .success(let report) = item.status {
                let reportBtn = NSButton(title: LocalizationManager.shared.string(.btnViewReport), target: self, action: #selector(viewReportAction(_:)))
                reportBtn.tag = row
                reportBtn.bezelStyle = .inline
                cellStack.addArrangedSubview(reportBtn)

                if report.destinationURL != nil {
                    let finderBtn = NSButton(title: LocalizationManager.shared.string(.btnFinder), target: self, action: #selector(revealInFinderAction(_:)))
                    finderBtn.tag = row
                    finderBtn.bezelStyle = .inline
                    cellStack.addArrangedSubview(finderBtn)
                }
            }
            return cellStack
        }

        return nil
    }

    @objc private func viewReportAction(_ sender: NSButton) {
        let row = sender.tag
        guard row < viewModel.items.count, case .success(let report) = viewModel.items[row].status else { return }

        let alert = NSAlert()
        alert.messageText = LocalizationManager.shared.string(.reportTitle)
        var lines: [String] = []
        lines.append(LocalizationManager.shared.format(.reportFile, report.sourceURL.lastPathComponent))
        lines.append(LocalizationManager.shared.string(.reportDivider))

        let mimeDetail = report.mimetypeCorrected ?
            LocalizationManager.shared.string(.reportMimetypeFixed) :
            LocalizationManager.shared.string(.reportMimetypeOK)
        lines.append(LocalizationManager.shared.format(.reportMimetype, mimeDetail))

        let containerDetail = report.containerCreated ?
            LocalizationManager.shared.string(.reportContainerCreated) :
            LocalizationManager.shared.string(.reportContainerOK)
        lines.append(LocalizationManager.shared.format(.reportContainer, containerDetail))

        lines.append(LocalizationManager.shared.format(.reportManifestAdded, report.manifestItemsAdded))
        lines.append(LocalizationManager.shared.format(.reportManifestRemoved, report.manifestItemsRemoved))
        lines.append(LocalizationManager.shared.format(.reportJunkRemoved, report.junkFilesRemoved))
        lines.append(LocalizationManager.shared.format(.reportSizeDifference, report.sizeDifferenceFormatted))

        if let dest = report.destinationURL {
            lines.append(LocalizationManager.shared.format(.reportOutputPath, dest.path))
        }

        if !report.logs.isEmpty {
            lines.append("")
            lines.append(LocalizationManager.shared.string(.reportDetailedLogs))
            for log in report.logs {
                lines.append("  - \(log)")
            }
        }

        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: LocalizationManager.shared.string(.alertBtnOK))
        alert.runModal()
    }

    @objc private func revealInFinderAction(_ sender: NSButton) {
        let row = sender.tag
        guard row < viewModel.items.count,
              case .success(let report) = viewModel.items[row].status,
              let dest = report.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dest])
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
