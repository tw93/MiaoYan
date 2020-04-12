//
//  AboutViewController.swift
//  FSNotes
//
//  Created by Олександр Глущенко on 5/10/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa

class AboutViewController: NSViewController {
    override func viewDidLoad() {
        if let dictionary = Bundle.main.infoDictionary,
            let ver = dictionary["CFBundleShortVersionString"] as? String,
            let build = dictionary["CFBundleVersion"] as? String {
            versionLabel.stringValue = "Version \(ver) (\(build))"
            versionLabel.isSelectable = true
        }
    }

    @IBOutlet weak var versionLabel: NSTextField!
    
    @IBAction func openContributorsPage(_ sender: Any) {
        let url = URL(string: "https://github.com/glushchenko/fsnotes/graphs/contributors")!
        NSWorkspace.shared.open(url)
    }
}
