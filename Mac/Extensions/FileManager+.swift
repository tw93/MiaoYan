//
//  FileManager+.swift
//  MiaoYan
//
//  Created by Tw93 on 2022/7/5.
//  Copyright © 2022 MiaoYan App. All rights reserved.
//

import Cocoa
extension FileManager {
    func directoryExists(atUrl url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = self.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
