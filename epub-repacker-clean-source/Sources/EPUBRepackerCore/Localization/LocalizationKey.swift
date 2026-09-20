import Foundation

/// Type-safe localization keys representing all UI and menu text in EPUB Repacker.
public enum LocalizationKey: String, CaseIterable, Sendable {
    // MARK: - Window & App Information
    case windowTitle

    // MARK: - Menu Bar
    case menuAbout
    case menuHide
    case menuHideOthers
    case menuShowAll
    case menuQuit
    case menuFile
    case menuOpenBooksSync
    case menuWindow
    case menuMinimize
    case menuZoom
    case menuLanguage
    case menuLanguageEnglish
    case menuLanguageChinese

    // MARK: - Drop Zone
    case dropTitle
    case dropSubtitle
    case browseButton

    // MARK: - Export Destination Settings
    case exportTitle
    case exportSameDir
    case exportAppleBooks
    case exportCustomDir
    case changeFolderButton
    case openBooksButton
    case openBooksTooltip
    case destCurrentSameDir
    case destCurrentAppleBooks
    case destCurrentCustom

    // MARK: - File Dialogs & System Actions
    case chooseFolderPrompt
    case booksOpenedInFinder
    case booksOpenFailed

    // MARK: - Queue Table View
    case colFileName
    case colStatus
    case colAction

    // MARK: - Status Updates
    case statusReady
    case statusItemsAdded
    case statusListCleared
    case statusProcessing
    case statusProgress
    case statusCompleted

    // MARK: - Item Status & Table Actions
    case itemStatusPending
    case itemStatusProcessing
    case itemStatusSuccess
    case itemStatusFailed
    case btnViewReport
    case btnFinder

    // MARK: - Control Buttons
    case btnClearQueue
    case btnStartRepack
    case btnCancel

    // MARK: - Alerts
    case alertEmptyTitle
    case alertEmptyMessage
    case alertBtnOK

    // MARK: - Repair & Repack Report Dialog
    case reportTitle
    case reportFile
    case reportDivider
    case reportMimetype
    case reportMimetypeFixed
    case reportMimetypeOK
    case reportContainer
    case reportContainerCreated
    case reportContainerOK
    case reportManifestAdded
    case reportManifestRemoved
    case reportJunkRemoved
    case reportSizeDifference
    case reportOutputPath
    case reportDetailedLogs
}
