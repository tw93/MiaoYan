import Cocoa
import Darwin

private let uploadServerURL = "http://127.0.0.1:36677/upload"

@MainActor
class ClipboardManager {
    private weak var textView: EditTextView?

    // Simplistic response model for PicGo/PicList
    struct PicGoResponse: Codable {
        let success: Bool
        let result: [String]
    }

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

    // Simplified parameters for uPic/Picsee
    struct UploadParameters {
        let localPath: String
        let originalPath: String
        let picType: String
        let textView: EditTextView
        let note: Note
        let viewController: ViewController
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

            // Only Support PicGo and PicList via HTTP
            if picType == "PicGo" || picType == "PicList" {
                vc.toastUpload(status: true)
                let defaultImageString = "![](\(path))"
                let serverURL = uploadServerURL

                postToPicGo(imagePath: imagePath, serverURL: serverURL) { [weak self, weak textView, weak vc] result, error in
                    Task { @MainActor in
                        let finalImage: NSAttributedString
                        if let resultString = result {
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
            } else if picType == "uPic" || picType == "Picsee" {
                // Restore uPic/Picsee support via Shell Command
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
            } else {
                // Default local storage
                textView.breakUndoCoalescing()
                textView.insertText(defaultImage, replacementRange: textView.selectedRange())
            }
        }
    }

    // MARK: - Process Execution for uPic/Picsee
    nonisolated private func run(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        // Set a default PATH to ensure tools can be found
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe

        // Capture stderr to console for debugging
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            print("MiaoYan Shell Error: \(error)")
            return nil
        }

        final class ProcessOutput: @unchecked Sendable {
            var outputData = Data()
            var errorData = Data()
        }

        let semaphore = DispatchSemaphore(value: 0)
        let result = ProcessOutput()

        // Read stdout and stderr in parallel to avoid pipe deadlock
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            result.outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            result.errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        DispatchQueue.global(qos: .utility).async {
            group.wait()
            process.waitUntilExit()
            semaphore.signal()
        }

        // Wait with timeout
        let waitResult = semaphore.wait(timeout: .now() + 10.0)
        if waitResult == .timedOut {
            // Try graceful termination first
            process.terminate()

            // If still running after 1 second, force kill
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            DispatchQueue.global(qos: .utility).async {
                semaphore.wait()
                if !result.errorData.isEmpty, let errorStr = String(data: result.errorData, encoding: .utf8) {
                    print("MiaoYan Shell Stderr: \(errorStr)")
                }
            }
            print("MiaoYan Shell Timeout: Command exceeded 10 seconds")
            return nil
        }

        // Print stderr if any
        if !result.errorData.isEmpty, let errorStr = String(data: result.errorData, encoding: .utf8) {
            print("MiaoYan Shell Stderr: \(errorStr)")
        }

        return String(data: result.outputData, encoding: .utf8)
    }

    nonisolated private func uploadToCloudAsync(parameters: UploadParameters) {
        let localPath = parameters.localPath
        let originalPath = parameters.originalPath
        let picType = parameters.picType
        let textView = parameters.textView
        let note = parameters.note

        DispatchQueue.global(qos: .userInitiated).async {
            let executablePath = "/Applications/\(picType).app/Contents/MacOS/\(picType)"
            let runList = self.run(executablePath: executablePath, arguments: ["-o", "url", "-u", localPath])
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

    private func postToPicGo(imagePath: String, serverURL: String, completion: @escaping @Sendable (String?, Error?) -> Void) {
        guard let url = URL(string: serverURL) else {
            completion(nil, NSError(domain: "Invalid URL", code: -1, userInfo: nil))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: [String]] = [
            "list": [imagePath]
        ]

        do {
            request.httpBody = try JSONEncoder().encode(parameters)
        } catch {
            completion(nil, error)
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(nil, error)
                return
            }

            guard let data = data else {
                completion(nil, NSError(domain: "No Data", code: -1, userInfo: nil))
                return
            }

            // PicGo returns { "success": true, "result": ["url"] }
            // PicList might return similar structure
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                    let result = json["result"] as? [String],
                    let firstUrl = result.first, !firstUrl.isEmpty
                {
                    completion(firstUrl, nil)
                } else {
                    completion(nil, nil)
                }
            } catch {
                completion(nil, error)
            }
        }
        task.resume()
    }

    @MainActor private func deleteImage(tempPath: URL) {
        do {
            guard let resultingItemUrl = Storage.sharedInstance().trashItem(url: tempPath) else { return }
            try FileManager.default.moveItem(at: tempPath, to: resultingItemUrl)
        } catch {
            AppDelegate.trackError(error, context: "ClipboardManager.deleteImage")
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
            }
        } catch {
        }
    }
}
