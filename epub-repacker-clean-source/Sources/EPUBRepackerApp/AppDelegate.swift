import AppKit
import EPUBRepackerCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = LocalizationManager.shared.string(.windowTitle)
        window.contentViewController = MainViewController()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        setupMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageDidChange(_:)),
            name: .appLanguageDidChange,
            object: nil
        )

        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupMenu() {
        let mainMenu = NSMenu()

        // 1. App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: LocalizationManager.shared.string(.menuAbout), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: LocalizationManager.shared.string(.menuHide), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: LocalizationManager.shared.string(.menuHideOthers), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: LocalizationManager.shared.string(.menuShowAll), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: LocalizationManager.shared.string(.menuQuit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // 2. File / Action Menu
        let fileTitle = LocalizationManager.shared.string(.menuFile)
        let fileMenuItem = NSMenuItem(title: fileTitle, action: nil, keyEquivalent: "")
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: fileTitle)
        fileMenuItem.submenu = fileMenu

        let openBooksItem = NSMenuItem(title: LocalizationManager.shared.string(.menuOpenBooksSync), action: #selector(openBooksFolderFromMenu), keyEquivalent: "b")
        fileMenu.addItem(openBooksItem)

        // 3. Language Menu
        let languageTitle = LocalizationManager.shared.string(.menuLanguage)
        let languageMenuItem = NSMenuItem(title: languageTitle, action: nil, keyEquivalent: "")
        mainMenu.addItem(languageMenuItem)
        let languageMenu = NSMenu(title: languageTitle)
        languageMenuItem.submenu = languageMenu

        let currentLang = LocalizationManager.shared.currentLanguage

        let englishItem = NSMenuItem(title: LocalizationManager.shared.string(.menuLanguageEnglish), action: #selector(selectLanguageFromMenu(_:)), keyEquivalent: "")
        englishItem.representedObject = AppLanguage.english
        englishItem.tag = 0
        englishItem.state = (currentLang == .english) ? .on : .off
        languageMenu.addItem(englishItem)

        let chineseItem = NSMenuItem(title: LocalizationManager.shared.string(.menuLanguageChinese), action: #selector(selectLanguageFromMenu(_:)), keyEquivalent: "")
        chineseItem.representedObject = AppLanguage.chinese
        chineseItem.tag = 1
        chineseItem.state = (currentLang == .chinese) ? .on : .off
        languageMenu.addItem(chineseItem)

        // 4. Window Menu
        let windowTitle = LocalizationManager.shared.string(.menuWindow)
        let windowMenuItem = NSMenuItem(title: windowTitle, action: nil, keyEquivalent: "")
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: windowTitle)
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: LocalizationManager.shared.string(.menuMinimize), action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: LocalizationManager.shared.string(.menuZoom), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
    }

    @objc private func handleLanguageDidChange(_ notification: Notification) {
        let update = { [weak self] in
            self?.setupMenu()
            self?.window?.title = LocalizationManager.shared.string(.windowTitle)
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    @objc private func selectLanguageFromMenu(_ sender: NSMenuItem) {
        if let lang = sender.representedObject as? AppLanguage {
            LocalizationManager.shared.setLanguage(lang)
        } else if sender.tag == 0 {
            LocalizationManager.shared.setLanguage(.english)
        } else if sender.tag == 1 {
            LocalizationManager.shared.setLanguage(.chinese)
        }
    }

    @objc private func openBooksFolderFromMenu() {
        _ = OutputOption.openAppleBooksDocumentsInFinder()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
