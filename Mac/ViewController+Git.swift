//
//  ViewController+Git.swift
//  FSNotes
//
//  Created by Олександр Глущенко on 9/10/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa

extension ViewController {

    @IBAction func saveRevision(_ sender: NSMenuItem) {
        guard let note = EditTextView.note else { return }

        let project = note.project.getParent()
        let repository = Git.sharedInstance().getRepository(by: project)
        let gitPath = note.getGitPath()

        repository.initialize(from: project)
        repository.commit(fileName: gitPath)
    }

    @IBAction func makeSnapshot(_ sender: NSMenuItem) {
        guard let project = ViewController.shared()?.getSidebarProject() else { return }

        DispatchQueue.global(qos: .background).async {
            let repository = Git.sharedInstance().getRepository(by: project.getParent())
            repository.initialize(from: project.getParent())
            repository.commitAll()
        }
    }

    @IBAction func checkoutRevision(_ sender: NSMenuItem) {
        guard let commit = sender.representedObject as? Commit else { return }
        guard let note = EditTextView.note else { return }

        let repository = Git.sharedInstance().getRepository(by: note.project.getParent())
        repository.checkout(commit: commit, fileName: note.getGitPath())

        _ = note.reload()
        NotesTextProcessor.highlight(note: note)
        refillEditArea()
        notesTableView.reloadRow(note: note)
    }

    public func loadHistory() {
        guard let vc = ViewController.shared(),
            let note = vc.notesTableView.getSelectedNote()
            else { return }

        let title = NSLocalizedString("History", comment: "")
        let historyMenu = noteMenu.item(withTitle: title)
        historyMenu?.submenu?.removeAllItems()

        DispatchQueue.global().async {
            let git = Git.sharedInstance()
            let repository = git.getRepository(by: note.project.getParent())
            let commits = repository.getCommits(by: note.getGitPath())

            DispatchQueue.main.async {
                guard commits.count > 0 else {
                    historyMenu?.isHidden = true
                    return
                }

                for commit in commits {
                    let menuItem = NSMenuItem()
                    if let date = commit.getDate() {
                        menuItem.title = date
                    }

                    menuItem.representedObject = commit
                    menuItem.action = #selector(vc.checkoutRevision(_:))
                    historyMenu?.submenu?.addItem(menuItem)
                }
            }
        }

        historyMenu?.isHidden = false
    }

    @IBAction private func makeFullSnapshot(_ sender: Any) {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: Date())
        let minute = cal.component(.minute, from: Date())

        if minute == lastSnapshot {
            return
        }

        lastSnapshot = minute

        guard UserDefaultsManagement.snapshotsInterval != 0 && (
            hour == UserDefaultsManagement.snapshotsInterval || (
                hour != 0 && hour % UserDefaultsManagement.snapshotsInterval == 0
            )
        ) else { return }

        guard UserDefaultsManagement.snapshotsIntervalMinutes == minute else { return }

        let storage = Storage.sharedInstance()
        let projects = storage.getProjects()

        for project in projects {
            if project.isTrash {
                continue
            }

            if project.isRoot || project.isArchive {
                let git = Git(storage: UserDefaultsManagement.gitStorage)
                let repo = git.getRepository(by: project)
                repo.commitAll()
            }
        }
    }

    public func scheduleSnapshots() {
        guard !UserDefaultsManagement.backupManually else { return }

        snapshotsTimer.invalidate()
        snapshotsTimer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(makeFullSnapshot), userInfo: nil, repeats: true)
    }
}
