import XCTest

@testable import MiaoYan

/// The print-operation PDF export hands its file to `saveToDownloadsWithFilename`,
/// which reports the outcome itself once the write has finished. The export's own
/// completion must not report success a second time, before the file exists.
final class ExportToastTests: XCTestCase {
    @MainActor
    func testSuccessfulPrintExportLeavesTheResultToastToTheSave() {
        let host = RecordingExportHost()
        MPreviewView.finishPrintExport(success: true, viewController: host)
        XCTAssertEqual(host.exportStatuses, [])
        XCTAssertEqual(host.dismissCount, 1)
    }

    @MainActor
    func testFailedPrintExportReportsFailureOnce() {
        let host = RecordingExportHost()
        MPreviewView.finishPrintExport(success: false, viewController: host)
        XCTAssertEqual(host.exportStatuses, [false])
    }

    /// A note removed during the shell's one-second wait leaves the host no
    /// note to export. Each export used to return silently, so the shell's
    /// busy flag (cleared only by toastExport or endExport) stuck until
    /// relaunch, blocking every later export and note switch.
    @MainActor
    func testExportsWithoutANoteFailAndEnd() {
        let host = RecordingExportHost()
        let previousShell = ExportHosts.shell
        ExportHosts.shell = host
        defer { ExportHosts.shell = previousShell }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("miaoyan-export-\(UUID().uuidString)")
        let note = Note(url: dir.appendingPathComponent("gone.md"), with: Project(url: dir, label: "export", isRoot: true))
        let preview = NoLoadPreviewView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), note: note, closure: nil)

        MPreviewView.exportHtml()
        preview.exportPdf()
        preview.exportImage()

        XCTAssertEqual(host.exportStatuses, [false, false, false])
    }

    /// The deck export also clears the print layout flag and leaves the
    /// slides it opened, or the next preview rendered as print pages.
    @MainActor
    func testDeckExportWithoutANoteClearsThePrintLayout() {
        let host = RecordingExportHost()
        let previousShell = ExportHosts.shell
        let previousExportPPT = UserDefaultsManagement.isOnExportPPT
        ExportHosts.shell = host
        UserDefaultsManagement.isOnExportPPT = true
        defer {
            ExportHosts.shell = previousShell
            UserDefaultsManagement.isOnExportPPT = previousExportPPT
        }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("miaoyan-export-\(UUID().uuidString)")
        let note = Note(url: dir.appendingPathComponent("gone.md"), with: Project(url: dir, label: "export", isRoot: true))
        let preview = NoLoadPreviewView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), note: note, closure: nil)

        preview.exportPPTOptimized()

        XCTAssertEqual(host.exportStatuses, [false])
        XCTAssertEqual(host.finishPPTCount, 1)
        XCTAssertFalse(UserDefaultsManagement.isOnExportPPT)
    }
}

@MainActor
private final class RecordingExportHost: ExportHost {
    var exportStatuses: [Bool] = []
    var dismissCount = 0
    var finishPPTCount = 0

    var exportNote: Note? { nil }
    var exportTitle: String { "" }
    func toastPersistent(message: String) {}
    func toastUpdate(message: String) {}
    func toastDismiss() { dismissCount += 1 }
    func toastExport(status: Bool) { exportStatuses.append(status) }
    func endExport() {}
    func finishPPTExport() { finishPPTCount += 1 }
}

@MainActor
private final class NoLoadPreviewView: MPreviewView {
    override func load(note: Note, force: Bool = false, completion: (() -> Void)? = nil) {}
}
