//
//  PreferencesSecurityViewController.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 3/17/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa
import LocalAuthentication

class PreferencesSecurityViewController: NSViewController {

    @IBOutlet weak var lockOnSleep: NSButton!
    @IBOutlet weak var lockOnScreenActivated: NSButton!
    @IBOutlet weak var lockWhenFastUser: NSButton!
    @IBOutlet weak var allowTouchID: NSButton!
    @IBOutlet weak var saveInKeychain: NSButton!
    @IBOutlet weak var masterPassword: NSButton!

    override func viewDidLoad() {
        lockOnSleep.state = UserDefaultsManagement.lockOnSleep ? .on : .off
        lockOnScreenActivated.state = UserDefaultsManagement.lockOnSleep ? .on : .off
        lockWhenFastUser.state = UserDefaultsManagement.lockOnUserSwitch ? .on : .off
        allowTouchID.state = UserDefaultsManagement.allowTouchID ? .on : .off
        saveInKeychain.state = UserDefaultsManagement.savePasswordInKeychain ? .on : .off
        masterPassword.isEnabled = UserDefaultsManagement.allowTouchID

        if #available(OSX 10.12.2, *), UserDefaultsManagement.allowTouchID {
            let context = LAContext()
            if !context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
                disableTouchID()
                return
            }
        } else {
            disableTouchID()
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        preferredContentSize = NSSize(width: 492, height: 352)
    }

    @IBAction func openMasterPasswordWindow(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }

        if let controller = vc.storyboard?.instantiateController(withIdentifier: "MasterPasswordViewController") as? MasterPasswordViewController {

            presentAsSheet(controller)
        }
    }

    @IBAction func lockOnSleep(_ sender: NSButton) {
        UserDefaultsManagement.lockOnSleep = (sender.state == .on)
    }

    @IBAction func lockOnScreenActivated(_ sender: NSButton) {
        UserDefaultsManagement.lockOnScreenActivated = (sender.state == .on)
    }

    @IBAction func lockWhenSwitched(_ sender: NSButton) {
        UserDefaultsManagement.lockOnUserSwitch = (sender.state == .on)
    }

    @IBAction func allowTouchID(_ sender: NSButton) {
        UserDefaultsManagement.allowTouchID = (sender.state == .on)

        masterPassword.isEnabled = UserDefaultsManagement.allowTouchID
    }

    @IBAction func saveInKeychain(_ sender: NSButton) {
        UserDefaultsManagement.savePasswordInKeychain = (sender.state == .on)
    }

    private func disableTouchID() {
        masterPassword.isEnabled = false
        allowTouchID.isEnabled = false
        allowTouchID.state = .off
        saveInKeychain.isEnabled = false
        saveInKeychain.state = .off
    }

}
