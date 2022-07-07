//
//  ContentViewController.swift
//  MiaoYan
//
//  Created by Tw93 on 2022/7/6.
//  Copyright © 2022 MiaoYan App. All rights reserved.
//

import AppKit

class ContentViewController: NSViewController, NSPopoverDelegate {
    @IBOutlet var wordCount: NSTextField!
    @IBOutlet var updateTime: NSTextField!
    @IBOutlet var createTime: NSTextField!

    func replace(validateString: String, regex: String, content: String) -> String {
        do {
            let RE = try NSRegularExpression(pattern: regex, options: .caseInsensitive)
            let modified = RE.stringByReplacingMatches(in: validateString, options: .reportProgress, range: NSRange(location: 0, length: validateString.count), withTemplate: content)
            return modified
        } catch {
            return validateString
        }
    }

    override func viewDidAppear() {
        guard let vc = ViewController.shared() else { return }
        let note = vc.notesTableView.getSelectedNote()
        var words = note?.getPrettifiedContent()

        words = replace(validateString: words!, regex: "*+", content: "")
        words = replace(validateString: words!, regex: "#+", content: "")
        words = replace(validateString: words!, regex: "\\r\n", content: "")
        words = replace(validateString: words!, regex: "\\n", content: "")
        words = replace(validateString: words!, regex: "\\s", content: "")

        wordCount.stringValue = String(words!.count)
        updateTime.stringValue = note?.getUpdateTime() ?? ""
        createTime.stringValue = note?.getCreateTime() ?? ""
        super.viewDidAppear()
    }
}
