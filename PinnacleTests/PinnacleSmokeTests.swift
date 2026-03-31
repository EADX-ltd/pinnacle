import XCTest

@testable import Pinnacle

@MainActor
final class PinnacleSmokeTests: XCTestCase {
    func testAppContainerServiceSmokeBehavior() async throws {
        let container = AppContainer.live

        XCTAssertFalse(container.recordingService.isRecording)
        try container.recordingService.startRecording()
        XCTAssertTrue(container.recordingService.isRecording)
        try container.recordingService.stopRecording()
        XCTAssertFalse(container.recordingService.isRecording)

        let key = PreferenceKey(name: "tests.smoke.bool", defaultValue: false)
        container.preferencesService.setValue(true, for: key)
        XCTAssertTrue(container.preferencesService.value(for: key))
        container.preferencesService.setValue(false, for: key)

        let status = await container.permissionService.refreshPermissions()
        XCTAssertEqual(status, .notDetermined)
    }
}
