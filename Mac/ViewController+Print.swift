//
//  ViewController+Print.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 2/15/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import WebKit

extension ViewController {

    @objc func allImagesLoaded(_ message: String) {}

    override class func isSelectorExcluded(fromWebScript sel: Selector) -> Bool {
        if sel == #selector(ViewController.allImagesLoaded(_:)) {
            return false
        }
        return true
    }

    override class func webScriptName(for sel: Selector) -> String? {
        if sel == #selector(ViewController.allImagesLoaded(_:)) {
            return "allImagesLoaded";
        }
        return nil
    }

    public func printMarkdownPreview(webView: WebView?) {
        guard let note = EditTextView.note else { return }

        let classBundle = Bundle(for: MarkdownView.self)
        let url = classBundle.url(forResource: "DownView", withExtension: "bundle")!
        let bundle = Bundle(url: url)!
        let baseURL = bundle.url(forResource: "index", withExtension: "html")!

        let markdownString = note.getPrettifiedContent()
        let css = MarkdownView.getPreviewStyle(theme: "atom-one-light") + "  .copyCode { display: none; } body { -webkit-text-size-adjust: none; font-size: 1.0em;} pre, code { border: 1px solid #c0c4ce; border-radius: 3px; } pre, pre code { word-wrap: break-word; }";

        var template = try! NSString(contentsOf: baseURL, encoding: String.Encoding.utf8.rawValue)
        template = template.replacingOccurrences(of: "DOWN_CSS", with: css) as NSString

        let html = renderMarkdownHTML(markdown: markdownString)!
        var htmlString = template.replacingOccurrences(of: "DOWN_HTML", with: html)
        var imagesStorage = note.project.url

        if note.isTextBundle() {
            imagesStorage = note.getURL()
        }

        htmlString = self.loadImages(imagesStorage: imagesStorage, html: htmlString)

        webView?.frameLoadDelegate = self
        webView?.mainFrame.loadHTMLString(htmlString, baseURL: baseURL)

        if UserDataService.instance.isDark {
            webView?.stringByEvaluatingJavaScript(from: "switchToDarkMode();")
        }
    }

    func webView(_ sender: WebView!, didFinishLoadFor frame: WebFrame!) {
        if sender.isLoading {
            return
        }
        if frame != sender.mainFrame {
            return
        }
        if sender.stringByEvaluatingJavaScript(from: "document.readyState") == "complete" {
            sender.frameLoadDelegate = nil

            let printInfo = NSPrintInfo.shared
            printInfo.paperSize = NSMakeSize(595.22, 841.85)
            printInfo.topMargin = 40.0
            printInfo.leftMargin = 40.0
            printInfo.rightMargin = 40.0
            printInfo.bottomMargin = 40.0

            let when = DispatchTime.now() + 0.2
            DispatchQueue.main.asyncAfter(deadline: when) {
                let operation: NSPrintOperation = NSPrintOperation(view: sender.mainFrame.frameView.documentView, printInfo: printInfo)
                operation.printPanel.options.insert(NSPrintPanel.Options.showsPaperSize)
                operation.printPanel.options.insert(NSPrintPanel.Options.showsOrientation)
                operation.run()
            }
        }
    }

    private func loadImages(imagesStorage: URL, html: String) -> String {
        var htmlString = html

        do {
            let regex = try NSRegularExpression(pattern: "<img.*?src=\"([^\"]*)\"")
            let results = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

            let images = results.map {
                String(html[Range($0.range(at: 0), in: html)!])
            }

            for image in images {

                let localPath = image.replacingOccurrences(of: "<img src=\"", with: "").dropLast()

                guard !localPath.starts(with: "http://") && !localPath.starts(with: "https://") else {
                    continue
                }

                let fullImageURL = imagesStorage
                let imageURL = fullImageURL.appendingPathComponent(String(localPath.removingPercentEncoding!))

                var orientation = 0
                let url = NSURL(fileURLWithPath: imageURL.path)
                if let imageSource = CGImageSourceCreateWithURL(url, nil) {
                    let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as Dictionary?
                    if let orientationProp = imageProperties?[kCGImagePropertyOrientation] as? Int {
                        orientation = orientationProp
                    }
                }

                let imageData = try Data(contentsOf: imageURL)
                let base64prefix = "<img data-orientation=\"\(orientation)\" class=\"fsnotes-preview\" src=\"data:image;base64," + imageData.base64EncodedString() + "\""
                htmlString = htmlString.replacingOccurrences(of: image, with: base64prefix)
            }
        } catch let error {
            print("Images regex: \(error.localizedDescription)")
        }

        return htmlString
    }
}
