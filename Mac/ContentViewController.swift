//
//  ContentViewController.swift
//  MiaoYan
//
//  Created by Tw93 on 2022/7/6.
//  Copyright © 2022 MiaoYan App. All rights reserved.
//

import AppKit

class ContentViewController: NSViewController {
    @IBOutlet var wordCount: NSTextField!
    @IBOutlet var updateTime: NSTextField!
    @IBOutlet var createTime: NSTextField!
    @IBOutlet var filePath: NSTextField!

    override func viewDidAppear(){
        guard let vc = ViewController.shared() else { return }
        wordCount.stringValue = vc.wordCount
        updateTime.stringValue = vc.updateTime
        createTime.stringValue = vc.createTime
        filePath.stringValue = vc.filePath
        super.viewDidAppear()
    }
}
