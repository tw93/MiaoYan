//
//  PreferencesAdvancedViewController.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 3/17/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa

class PreferencesAdvancedViewController: NSViewController {
    override func viewWillAppear() {
        super.viewWillAppear()
        preferredContentSize = NSSize(width: 464, height: 440)
    }

    @IBOutlet weak var archivePathControl: NSPathControl!
    @IBOutlet weak var languagePopUp: NSPopUpButton!
    @IBOutlet weak var version: NSTextField!
    @IBOutlet weak var appearance: NSPopUpButton!
    @IBOutlet weak var appearanceLabel: NSTextField!

    @IBOutlet weak var dockIconFirst: NSButton!
    @IBOutlet weak var dockIconSecond: NSButton!

    @IBOutlet weak var markdownPreviewCSS: NSPathControl!

    @IBAction func appearanceClick(_ sender: NSPopUpButton) {
        if let type = AppearanceType(rawValue: sender.indexOfSelectedItem) {
            UserDefaultsManagement.appearanceType = type

            if type == .Dark {
                UserDefaultsManagement.codeTheme = "monokai-sublime"
            } else if type == .System {
                if #available(OSX 10.14, *) {
                    let mode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")

                    if mode == "Dark" {
                        UserDefaultsManagement.codeTheme = "monokai-sublime"
                    }
                }
            } else {
                UserDefaultsManagement.codeTheme = "atom-one-light"
            }
        }

        restart()
    }

    override func viewDidAppear() {
        if let archiveDirectory = UserDefaultsManagement.archiveDirectory {
            archivePathControl.url = archiveDirectory
        }

        let languages = [
            LanguageType(rawValue: 0x00),
            LanguageType(rawValue: 0x01),
            LanguageType(rawValue: 0x02),
            LanguageType(rawValue: 0x03),
            LanguageType(rawValue: 0x04),
            LanguageType(rawValue: 0x05),
            LanguageType(rawValue: 0x06),
            LanguageType(rawValue: 0x07)
        ]

        for language in languages {
            if let lang = language?.description, let id = language?.rawValue {
                languagePopUp.addItem(withTitle: lang)
                languagePopUp.lastItem?.state = (id == UserDefaultsManagement.defaultLanguage) ? .on : .off

                if id == UserDefaultsManagement.defaultLanguage {
                    languagePopUp.selectItem(withTitle: lang)
                }
            }
        }

        if #available(OSX 10.14, *) {
            appearance.selectItem(at: UserDefaultsManagement.appearanceType.rawValue)
        } else {
            appearanceLabel.isHidden = true
            appearance.isHidden = true
        }

        if let dictionary = Bundle.main.infoDictionary,
            let ver = dictionary["CFBundleShortVersionString"] as? String,
            let build = dictionary["CFBundleVersion"] as? String {
            version.stringValue = "v\(ver) build \(build)"
        }

        switch UserDefaultsManagement.dockIcon {
        case 0:
            dockIconFirst.state = .on
            break
        case 1:
            dockIconSecond.state = .on
            break
        default:
            dockIconFirst.state = .on
        }

        if let preview = UserDefaultsManagement.markdownPreviewCSS {
            markdownPreviewCSS.url = preview
        }
    }

    @IBAction func changeArchiveStorage(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false
        openPanel.begin { (result) -> Void in
            if result.rawValue == NSFileHandlingPanelOKButton {
                guard let url = openPanel.url else { return }
                guard let currentURL = UserDefaultsManagement.archiveDirectory else { return }

                let bookmark = SandboxBookmark.sharedInstance()
                _ = bookmark.load()
                bookmark.remove(url: currentURL)
                bookmark.store(url: url)
                bookmark.save()

                UserDefaultsManagement.archiveDirectory = url
                self.archivePathControl.url = url

                let storage = Storage.sharedInstance()
                guard let vc = ViewController.shared() else { return }

                if let archive = storage.getArchive() {
                    archive.url = url
                    storage.unload(project: archive)
                    storage.loadLabel(archive)

                    vc.fsManager?.restart()
                    vc.notesTableView.reloadData()
                    vc.storageOutlineView.reloadData()
                    vc.storageOutlineView.selectArchive()
                }
            }
        }
    }

    @IBAction func changeMarkdownStyle(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = true
        openPanel.allowedFileTypes = ["css"]
        openPanel.begin { (result) -> Void in
            if result.rawValue == NSFileHandlingPanelOKButton {
                guard let url = openPanel.url else { return }

                let bookmark = SandboxBookmark.sharedInstance()
                _ = bookmark.load()
                
                if let currentURL = UserDefaultsManagement.markdownPreviewCSS {
                    bookmark.remove(url: currentURL)
                }

                bookmark.store(url: url)
                bookmark.save()

                UserDefaultsManagement.markdownPreviewCSS = url
                self.markdownPreviewCSS.url = url

                let webkitPreview = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wkPreview")

                try? FileManager.default.removeItem(at: webkitPreview)

                guard let vc = ViewController.shared() else { return }
                vc.refillEditArea()
            }
        }
    }

    @IBAction func languagePopUp(_ sender: NSPopUpButton) {
        let type = LanguageType.withName(rawValue: sender.title)

        UserDefaultsManagement.defaultLanguage = type.rawValue

        UserDefaults.standard.set([type.code], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()

        restart()
    }

    private func restart() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        exit(0)
    }

    @IBAction func dockIcon(_ sender: NSButton) {
        UserDefaultsManagement.dockIcon = sender.tag

        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
        appDelegate.loadDockIcon()
    }

}
