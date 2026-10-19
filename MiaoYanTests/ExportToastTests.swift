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
}

@MainActor
private final class RecordingExportHost: ExportHost {
    var exportStatuses: [Bool] = []
    var dismissCount = 0

    var exportNote: Note? { nil }
    var exportTitle: String { "" }
    func toastPersistent(message: String) {}
    func toastUpdate(message: String) {}
    func toastDismiss() { dismissCount += 1 }
    func toastExport(status: Bool) { exportStatuses.append(status) }
    func endExport() {}
    func finishPPTExport() {}
}
