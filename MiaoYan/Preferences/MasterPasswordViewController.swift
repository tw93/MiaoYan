//
//  MasterPasswordViewController.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 3/20/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa

class MasterPasswordViewController: NSViewController {
    override func viewDidAppear() {
        hint.stringValue = UserDefaultsManagement.masterPasswordHint
    }

    @IBOutlet weak var hint: NSTextField!

    @IBOutlet weak var currentPassword: NSSecureTextField!

    @IBOutlet weak var newPassword: NSSecureTextField!

    @IBOutlet weak var repeatedPassword: NSSecureTextField!


    @IBAction func close(_ sender: Any) {
        dismiss(self)
    }

    @IBAction func change(_ sender: Any) {
        var password = String()

        do {
            let item = KeychainPasswordItem(service: KeychainConfiguration.serviceName, account: "Master Password")
            password = try item.readPassword()
        } catch {
            print(error)
        }
        
        if password.count > 0, currentPassword.stringValue != password {
            wrongCurrentPassword()
            return
        }

        if newPassword.stringValue != repeatedPassword.stringValue {
            wrongRepeatAlert()
            return
        }

        if newPassword.stringValue.count == 0 {
            emptyPassword()
            return
        }

        let item = KeychainPasswordItem(service: KeychainConfiguration.serviceName, account: "Master Password")
        do {
            try item.savePassword(newPassword.stringValue)
        } catch {
            print("Master password saving error: \(error)")
        }

        UserDefaultsManagement.masterPasswordHint = hint.stringValue

        dismiss(self)
    }

    private func wrongRepeatAlert() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.informativeText = NSLocalizedString("Please try again", comment: "")
        alert.messageText = NSLocalizedString("Wrong repeated password", comment: "")
        alert.runModal()
    }

    private func wrongCurrentPassword() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.informativeText = NSLocalizedString("Please try again", comment: "")
        alert.messageText = NSLocalizedString("Current password does not match with password in keychain", comment: "")
        alert.runModal()
    }

    private func emptyPassword() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.informativeText = NSLocalizedString("Please try again", comment: "")
        alert.messageText = NSLocalizedString("Empty password", comment: "")
        alert.runModal()
    }

}

