import Testing
@testable import AppResetKit

@Suite("TCCServiceCatalog")
struct TCCServiceCatalogTests {
    @Test("Known services resolve to friendly names")
    func knownService() {
        #expect(TCCServiceCatalog.friendlyName(for: "kTCCServiceCamera") == "Camera")
        #expect(TCCServiceCatalog.friendlyName(for: "kTCCServiceSystemPolicyAllFiles") == "Full Disk Access")
    }

    @Test("Unknown services fall back to a humanised name")
    func unknownService() {
        #expect(TCCServiceCatalog.friendlyName(for: "kTCCServiceScreenCaptureExtra") == "Screen Capture Extra")
    }

    @Test("Usage-description keys map to services")
    func usageMapping() {
        #expect(TCCServiceCatalog.service(forUsageDescriptionKey: "NSCameraUsageDescription") == "kTCCServiceCamera")
        #expect(TCCServiceCatalog.service(forEntitlement: "com.apple.security.device.microphone") == "kTCCServiceMicrophone")
    }
}
