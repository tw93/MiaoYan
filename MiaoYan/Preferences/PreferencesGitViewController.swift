//
//  PreferencesGitViewController.swift
//  FSNotes
//
//  Created by Олександр Глущенко on 9/8/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa

class PreferencesGitViewController: NSViewController {

    @IBOutlet weak var repositoriesPath: NSPathControl!
    @IBOutlet weak var snapshotsTextField: NSTextField!
    @IBOutlet weak var minutes: NSTextField!
    @IBOutlet weak var gitVersion: NSTextField!
    @IBOutlet weak var backupManually: NSButton!
    @IBOutlet weak var backupBySchedule: NSButton!


    override func viewWillAppear() {
        super.viewWillAppear()
        preferredContentSize = NSSize(width: 476, height: 352)

        DispatchQueue.global().async {
            if let version = Git.sharedInstance().getVersion() {
                let allowedCharset = CharacterSet
                    .decimalDigits
                    .union(CharacterSet(charactersIn: "."))

                DispatchQueue.main.async {
                    self.gitVersion.stringValue = String(version.unicodeScalars.filter(allowedCharset.contains))
                }
            }
        }

        repositoriesPath.url = UserDefaultsManagement.gitStorage

        snapshotsTextField.stringValue = String(UserDefaultsManagement.snapshotsInterval)

        minutes.stringValue = String(UserDefaultsManagement.snapshotsIntervalMinutes)

        backupManually.state = UserDefaultsManagement.backupManually ? .on : .off
        backupBySchedule.state = UserDefaultsManagement.backupManually ? .off : .on
    }

    @IBAction func changeGitStorage(_ sender: NSButton) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false
        openPanel.begin { (result) -> Void in
            if result.rawValue == NSFileHandlingPanelOKButton {
                guard let url = openPanel.url else { return }
                let currentURL = UserDefaultsManagement.gitStorage

                let bookmark = SandboxBookmark.sharedInstance()
                _ = bookmark.load()
                bookmark.remove(url: currentURL)
                bookmark.store(url: url)
                bookmark.save()

                UserDefaultsManagement.gitStorage = url
                self.repositoriesPath.url = url

                Git.resetInstance()
            }
        }
    }

    @IBAction func showFinder(_ sender: Any) {
        NSWorkspace.shared.activateFileViewerSelecting([UserDefaultsManagement.gitStorage])
    }

    @IBAction func showTerminal(_ sender: Any) {
        NSWorkspace.shared.openFile(UserDefaultsManagement.gitStorage.path, withApplication: "Terminal.app")
    }

    @IBAction func backupMethod(_ sender: NSButton) {
        guard let ident = sender.identifier?.rawValue else { return }

        let isManualBackup = ident == "manual"

        UserDefaultsManagement.backupManually = isManualBackup
        backupManually.state = isManualBackup ? .on : .off
        backupBySchedule.state = isManualBackup ? .off : .on
    }


    @IBAction func changeSnapshotIntervalByHours(_ sender: NSTextField) {
        if let interval = Int(sender.stringValue) {
            UserDefaultsManagement.snapshotsInterval = interval
        }

        guard let vc = ViewController.shared() else { return }
        vc.scheduleSnapshots()
    }

    @IBAction func changeSnapshotsIntervalByMinutes(_ sender: NSTextField) {
        if let interval = Int(sender.stringValue) {
            UserDefaultsManagement.snapshotsIntervalMinutes = interval
        }

        guard let vc = ViewController.shared() else { return }
        vc.scheduleSnapshots()
    }

}
