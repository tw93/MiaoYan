import Alamofire
import Cocoa
import SwiftyJSON

struct UploadParameters {
    let localPath: String
    let originalPath: String
    let picType: String
    let textView: EditTextView
    let note: Note
    let viewController: ViewController
}

@MainActor
class ClipboardManager {
    private weak var textView: EditTextView?

    init(textView: EditTextView) {
        self.textView = textView
    }

    func handleCopy() -> Bool {
        guard let textView = textView else { return false }

        if textView.selectedRanges.count > 1 {
            let combined = String()
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(combined.trim().removeLastNewLine(), forType: NSPasteboard.PasteboardType.string)
            return true
        }

        if textView.selectedRange.length == 0,
            let paragraphRange = textView.getParagraphRange(),
            let paragraph = textView.attributedSubstring(forProposedRange: paragraphRange, actualRange: nil)
        {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(paragraph.string.trim().removeLastNewLine(), forType: NSPasteboard.PasteboardType.string)
            return true
        }

        return false
    }

    func handlePaste(in note: Note) -> Bool {
        guard let textView = textView else { return false }

        if let clipboard = NSPasteboard.general.string(forType: NSPasteboard.PasteboardType.string),
            NSPasteboard.general.string(forType: NSPasteboard.PasteboardType.fileURL) == nil
        {

            EditTextView.shouldForceRescan = true
            let currentRange = textView.selectedRange()
            textView.breakUndoCoalescing()
            textView.insertText(clipboard, replacementRange: currentRange)
            textView.saveTextStorageContent(to: note)
            note.save()
            textView.fillHighlightLinks()
            return true
        }

        return pasteImageFromClipboard(in: note)
    }

    private func pasteImageFromClipboard(in note: Note) -> Bool {
        guard let textView = textView else { return false }

        if let url = NSURL(from: NSPasteboard.general) {
            if !url.isFileURL {
                return false
            }
            return saveFile(url: url as URL, in: note)
        }

        if let clipboard = NSPasteboard.general.data(forType: .tiff),
            let image = NSImage(data: clipboard),
            let jpgData = image.jpgData
        {

            EditTextView.shouldForceRescan = true
            saveClipboard(data: jpgData, note: note)
            textView.saveTextStorageContent(to: note)
            note.save()
            textView.textStorage?.sizeAttachmentImages()
            return true
        }

        return false
    }

    func saveFile(url: URL, in note: Note) -> Bool {
        guard let textView = textView else { return false }

        if let data = try? Data(contentsOf: url) {
            var ext: String?

            if NSImage(data: data) != nil {
                ext = "jpg"
                if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                    let uti = CGImageSourceGetType(source)
                    if let fileExtension = (uti as String?)?.utiFileExtension {
                        ext = fileExtension
                    }
                }
            }

            EditTextView.shouldForceRescan = true
            saveClipboard(data: data, note: note, ext: ext, url: url)
            textView.saveTextStorageContent(to: note)
            note.save()
            textView.textStorage?.sizeAttachmentImages()
            return true
        }

        return false
    }

    private func saveClipboard(data: Data, note: Note, ext: String? = nil, url: URL? = nil) {
        guard let textView = textView,
            let vc = ViewController.shared()
        else { return }

        if let path = ImagesProcessor.writeFile(data: data, url: url, note: note, ext: ext) {
            let defaultImage = NSAttributedString(string: "![](\(path))")
            let imagePath = "\(note.project.url.path)\(path)"
            let tempPath = URL(fileURLWithPath: imagePath)
            let picType = UserDefaultsManagement.defaultPicUpload

            if picType == "PicGo" {
                vc.toastUpload(status: true)
                let defaultImageString = "![](\(path))"
                postToPicGo(imagePath: imagePath) { [weak self, weak textView, weak vc] result, error in
                    let resultString = result as? String
                    Task { @MainActor in
                        let finalImage: NSAttributedString
                        if let resultString = resultString {
                            finalImage = NSAttributedString(string: "![](\(resultString))")
                            self?.deleteImage(tempPath: tempPath)
                        } else {
                            finalImage = NSAttributedString(string: defaultImageString)
                            if let error = error {
                                vc?.toastUpload(status: false)
                                AppDelegate.trackError(error, context: "ClipboardManager.uploadToCloudAsync")
                            } else {
                                vc?.toastUpload(status: false)
                            }
                        }
                        textView?.breakUndoCoalescing()
                        textView?.insertText(finalImage, replacementRange: textView?.selectedRange() ?? NSRange(location: 0, length: 0))
                    }
                }
            } else {
                if picType == "uPic" || picType == "Picsee" {
                    let uploadingPlaceholder = NSAttributedString(string: "![](uploading...)")
                    textView.breakUndoCoalescing()
                    textView.insertText(uploadingPlaceholder, replacementRange: textView.selectedRange())

                    let uploadParams = UploadParameters(
                        localPath: tempPath.path,
                        originalPath: path,
                        picType: picType,
                        textView: textView,
                        note: note,
                        viewController: vc
                    )
                    uploadToCloudAsync(parameters: uploadParams)
                    return
                }
                textView.breakUndoCoalescing()
                textView.insertText(defaultImage, replacementRange: textView.selectedRange())
            }
        }
    }

    private func postToPicGo(imagePath: String, completion: @escaping @Sendable (Any?, Error?) -> Void) {
        let parameters: [String: [String]] = [
            "list": [imagePath]
        ]
        AF.request("http://127.0.0.1:36677/upload", method: .post, parameters: parameters, encoder: JSONParameterEncoder.default).response { response in
            switch response.result {
            case .success:
                let json = JSON(response.value as Any)
                let result = json["result"][0].stringValue
                if !result.isEmpty {
                    completion(result, nil)
                } else {
                    completion(nil, nil)
                }
            case .failure:
                completion(nil, nil)
            }
        }
    }

    @MainActor private func deleteImage(tempPath: URL) {
        do {
            guard let resultingItemUrl = Storage.sharedInstance().trashItem(url: tempPath) else { return }
            try FileManager.default.moveItem(at: tempPath, to: resultingItemUrl)
        } catch {
            AppDelegate.trackError(error, context: "ClipboardManager.deleteImage")
        }
    }

    nonisolated private func run(_ cmd: String) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = ["-c", String(format: "%@", cmd)]
        process.standardOutput = pipe
        let fileHandle = pipe.fileHandleForReading
        process.launch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            process.terminate()
        }
        process.waitUntilExit()
        return String(data: fileHandle.readDataToEndOfFile(), encoding: .utf8)
    }

    nonisolated private func uploadToCloudAsync(parameters: UploadParameters) {
        // Extract the data we need for the background task
        let localPath = parameters.localPath
        let originalPath = parameters.originalPath
        let picType = parameters.picType
        let textView = parameters.textView
        let note = parameters.note

        DispatchQueue.global(qos: .userInitiated).async {
            let command = "/Applications/\(picType).app/Contents/MacOS/\(picType) -o url -u \"\(localPath)\""
            let runList = self.run(command)
            let imageDesc = runList?.components(separatedBy: "\n") ?? []

            var uploadedURL: String?
            for line in imageDesc {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedLine.hasPrefix("http://") || trimmedLine.hasPrefix("https://") {
                    uploadedURL = trimmedLine
                    break
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let validURL = uploadedURL {
                    self.replacePlaceholderWithURL(
                        placeholder: "![](uploading...)",
                        cloudURL: validURL,
                        textView: textView,
                        note: note
                    )
                    self.deleteImage(tempPath: URL(fileURLWithPath: localPath))
                    if let viewController = textView.window?.contentViewController {
                        viewController.toast(message: I18n.str("Image uploaded successfully"))
                    }
                } else {
                    self.replacePlaceholderWithURL(
                        placeholder: "![](uploading...)",
                        cloudURL: originalPath,
                        textView: textView,
                        note: note
                    )
                    if let viewController = textView.window?.contentViewController {
                        viewController.toast(message: I18n.str("Image upload failed, using local path"))
                    }
                }
            }
        }
    }

    private func replacePlaceholderWithURL(placeholder: String, cloudURL: String, textView: EditTextView, note: Note) {
        guard let storage = textView.textStorage else { return }

        let content = storage.string
        let placeholderPattern = NSRegularExpression.escapedPattern(for: placeholder)

        do {
            let regex = try NSRegularExpression(pattern: placeholderPattern, options: [])
            let range = NSRange(location: 0, length: content.count)
            let replacement = "![](\(cloudURL))"

            if let match = regex.firstMatch(in: content, options: [], range: range) {
                storage.replaceCharacters(in: match.range, with: replacement)
                textView.saveTextStorageContent(to: note)
                note.save()
            } else {
            }
        } catch {
        }
    }
}
