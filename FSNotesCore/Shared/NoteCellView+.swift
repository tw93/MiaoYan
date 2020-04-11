//
//  NoteCellView+.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 11/6/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

#if os(iOS)
import UIKit
typealias ImageView = UIImageView
#else
import Cocoa
typealias ImageView = NSImageView
#endif

extension NoteCellView {
    public func loadImagesPreview(position: Int? = nil, urls: [URL]? = nil) {
        DispatchQueue.global(qos: .userInteractive).async {
            let current = Date().toMillis()
            self.timestamp = current
        }
    }
}
