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
        guard let note = self.note else { return }

        let imageURLs = urls ?? note.getImagePreviewUrl()
        let imagesFound = imageURLs?.count ?? 0

        guard
            !UserDefaultsManagement.hidePreviewImages &&
            !UserDefaultsManagement.horizontalOrientation else {
            return
        }

        hideUnusedImagesPreview(quantity: imagesFound)

        DispatchQueue.global(qos: .userInteractive).async {
            let current = Date().toMillis()
            self.timestamp = current

            if let images = imageURLs, images.count > 0 {
                let resizedImages = self.getResizedPreviewImages(note: note, images: images, timestamp: current!)

                DispatchQueue.main.async {
                    if current != self.timestamp {
                        return
                    }

                    self.attachImagesPreview(resizedImages: resizedImages)
                    self.fixTopConstraint(position: position, note: note)
                }
            }
        }
    }

    private func hideUnusedImagesPreview(quantity: Int) {
        if quantity < 3 {
            self.imagePreviewThird.image = nil
            self.imagePreviewThird.isHidden = true
        }

        if quantity < 2 {
            self.imagePreviewSecond.image = nil
            self.imagePreviewSecond.isHidden = true
        }

        if quantity < 1 {
            self.imagePreview.image = nil
            self.imagePreview.isHidden = true
        }
    }

    private func attachImagesPreview(resizedImages: [Image]) {
        var index = 0
        for resized in resizedImages {
            index += 1

            switch index {
            case 1:
                self.imagePreview.image = resized
                self.styleImageView(imageView: self.imagePreview)
            case 2:
                self.imagePreviewSecond.image = resized
                self.styleImageView(imageView: self.imagePreviewSecond)
            case 3:
                self.imagePreviewThird.image = resized
                self.styleImageView(imageView: self.imagePreviewThird)
            default:
                break
            }
        }
    }

    public func getResizedPreviewImages(note: Note, images: [URL], timestamp: Int64 = 00) -> [Image] {
        var resizedImages: [Image] = []

        for imageUrl in images {
            if timestamp != self.timestamp {
                return []
            }

            if let image = getPreviewImage(imageUrl: imageUrl, note: note) {
                resizedImages.append(image)
            }
        }

        return resizedImages
    }
}
