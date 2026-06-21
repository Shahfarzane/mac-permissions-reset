import Foundation

/// Static description of a TCC service.
public struct TCCServiceInfo: Sendable, Hashable {
    public let identifier: String          // kTCCService…
    public let name: String                // human label
    public let summary: String             // short explanation
    public let scope: TCCDatabaseScope     // which TCC.db it usually lives in

    public init(identifier: String, name: String, summary: String, scope: TCCDatabaseScope) {
        self.identifier = identifier
        self.name = name
        self.summary = summary
        self.scope = scope
    }
}

/// Friendly names and explanations for the macOS TCC privacy services, plus the
/// mapping from Info.plist usage-description keys and sandbox entitlements to the
/// services they correspond to. Service identifiers were enumerated from the
/// system TCC framework on macOS 27.
public enum TCCServiceCatalog {
    public static let all: [TCCServiceInfo] = [
        // Personal data (user TCC.db)
        .init(identifier: "kTCCServiceAddressBook", name: "Contacts", summary: "Access to your contacts.", scope: .user),
        .init(identifier: "kTCCServiceContactsLimited", name: "Contacts (Limited)", summary: "Limited access to your contacts.", scope: .user),
        .init(identifier: "kTCCServiceContactsFull", name: "Contacts (Full)", summary: "Full access to your contacts.", scope: .user),
        .init(identifier: "kTCCServiceCalendar", name: "Calendar", summary: "Access to your calendars.", scope: .user),
        .init(identifier: "kTCCServiceReminders", name: "Reminders", summary: "Access to your reminders.", scope: .user),
        .init(identifier: "kTCCServicePhotos", name: "Photos", summary: "Access to your photo library.", scope: .user),
        .init(identifier: "kTCCServicePhotosAdd", name: "Photos (Add Only)", summary: "Permission to add to your photo library.", scope: .user),
        .init(identifier: "kTCCServiceMediaLibrary", name: "Media & Apple Music", summary: "Access to your media library.", scope: .user),

        // Devices & sensors
        .init(identifier: "kTCCServiceCamera", name: "Camera", summary: "Access to the camera.", scope: .user),
        .init(identifier: "kTCCServiceMicrophone", name: "Microphone", summary: "Access to the microphone.", scope: .user),
        .init(identifier: "kTCCServiceAudioCapture", name: "Audio Recording", summary: "Capture of system or app audio.", scope: .user),
        .init(identifier: "kTCCServiceBluetoothAlways", name: "Bluetooth", summary: "Access to Bluetooth.", scope: .user),
        .init(identifier: "kTCCServiceMotion", name: "Motion & Fitness", summary: "Access to motion data.", scope: .user),
        .init(identifier: "kTCCServiceLocation", name: "Location", summary: "Access to your location.", scope: .user),
        .init(identifier: "kTCCServiceNearbyInteraction", name: "Nearby Interaction", summary: "Interaction with nearby devices.", scope: .user),
        .init(identifier: "kTCCServiceFaceID", name: "Face ID", summary: "Use of Face ID.", scope: .user),

        // Speech, tracking, sharing
        .init(identifier: "kTCCServiceSpeechRecognition", name: "Speech Recognition", summary: "Use of speech recognition.", scope: .user),
        .init(identifier: "kTCCServiceSiri", name: "Siri", summary: "Integration with Siri.", scope: .user),
        .init(identifier: "kTCCServiceUserTracking", name: "App Tracking", summary: "Tracking across apps and websites.", scope: .user),
        .init(identifier: "kTCCServicePasteboard", name: "Paste from Other Apps", summary: "Reading the pasteboard from other apps.", scope: .user),
        .init(identifier: "kTCCServiceShareKit", name: "Sharing", summary: "Use of sharing services.", scope: .user),
        .init(identifier: "kTCCServiceWillow", name: "Home", summary: "Access to HomeKit-enabled accessories.", scope: .user),
        .init(identifier: "kTCCServiceUbiquity", name: "iCloud", summary: "Access to iCloud data.", scope: .user),

        // Automation & input (system-scoped)
        .init(identifier: "kTCCServiceAppleEvents", name: "Automation", summary: "Controlling other apps via Apple Events.", scope: .user),
        .init(identifier: "kTCCServiceAccessibility", name: "Accessibility", summary: "Control of your computer via the accessibility API.", scope: .system),
        .init(identifier: "kTCCServicePostEvent", name: "Synthetic Input", summary: "Sending synthetic keyboard and mouse events.", scope: .system),
        .init(identifier: "kTCCServiceListenEvent", name: "Input Monitoring", summary: "Monitoring keyboard and mouse input.", scope: .system),
        .init(identifier: "kTCCServiceScreenCapture", name: "Screen & System Audio Recording", summary: "Recording the screen and system audio.", scope: .system),
        .init(identifier: "kTCCServiceRemoteDesktop", name: "Remote Desktop", summary: "Remote control of this Mac.", scope: .system),
        .init(identifier: "kTCCServiceDeveloperTool", name: "Developer Tools", summary: "Running software not subject to extra security checks.", scope: .system),
        .init(identifier: "kTCCServiceEndpointSecurityClient", name: "Endpoint Security", summary: "Use of the Endpoint Security API.", scope: .system),

        // Files & folders (system policy)
        .init(identifier: "kTCCServiceSystemPolicyAllFiles", name: "Full Disk Access", summary: "Access to all files on the system.", scope: .system),
        .init(identifier: "kTCCServiceSystemPolicyDesktopFolder", name: "Desktop Folder", summary: "Access to your Desktop folder.", scope: .user),
        .init(identifier: "kTCCServiceSystemPolicyDocumentsFolder", name: "Documents Folder", summary: "Access to your Documents folder.", scope: .user),
        .init(identifier: "kTCCServiceSystemPolicyDownloadsFolder", name: "Downloads Folder", summary: "Access to your Downloads folder.", scope: .user),
        .init(identifier: "kTCCServiceSystemPolicyNetworkVolumes", name: "Network Volumes", summary: "Access to network volumes.", scope: .user),
        .init(identifier: "kTCCServiceSystemPolicyRemovableVolumes", name: "Removable Volumes", summary: "Access to removable volumes.", scope: .user),
        .init(identifier: "kTCCServiceSystemPolicyDeveloperFiles", name: "Developer Files", summary: "Access to files in developer locations.", scope: .user),
        .init(identifier: "kTCCServiceSystemPolicyAppData", name: "Other Apps' Data", summary: "Access to other applications' data.", scope: .system),
        .init(identifier: "kTCCServiceSystemPolicyAppBundles", name: "App Management", summary: "Modifying other apps and their data.", scope: .system),
        .init(identifier: "kTCCServiceSystemPolicySysAdminFiles", name: "Admin Files", summary: "Access to system administration files.", scope: .system),
        .init(identifier: "kTCCServiceFileProviderDomain", name: "File Provider", summary: "Access to managed file-provider domains.", scope: .user),
        .init(identifier: "kTCCServiceFileProviderPresence", name: "File Provider Presence", summary: "Awareness of file-provider activity.", scope: .user),

        // Focus / status
        .init(identifier: "kTCCServiceFocusStatus", name: "Focus Status", summary: "Access to your Focus status.", scope: .user),
        .init(identifier: "kTCCServiceAccessibilityFocusStatus", name: "Accessibility Focus Status", summary: "Access to accessibility focus status.", scope: .user),
    ]

    /// Identifier → info, for O(1) lookup.
    public static let byIdentifier: [String: TCCServiceInfo] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.identifier, $0) })
    }()

    public static func info(for identifier: String) -> TCCServiceInfo? {
        byIdentifier[identifier]
    }

    /// Friendly label for a service identifier, falling back to a humanised form
    /// of the raw `kTCCService…` string for services not in the catalog.
    public static func friendlyName(for identifier: String) -> String {
        if let info = byIdentifier[identifier] { return info.name }
        var stripped = identifier
        if stripped.hasPrefix("kTCCService") {
            stripped.removeFirst("kTCCService".count)
        }
        // Insert spaces before capital letters: "ScreenCapture" -> "Screen Capture".
        var result = ""
        for (index, char) in stripped.enumerated() {
            if index > 0, char.isUppercase { result.append(" ") }
            result.append(char)
        }
        return result.isEmpty ? identifier : result
    }

    // MARK: - Declared-permission mappings

    /// Map a sandbox entitlement key to the TCC service it corresponds to (if any).
    public static func service(forEntitlement key: String) -> String? {
        entitlementToService[key]
    }

    /// Map an Info.plist `NS…UsageDescription` key to a TCC service (if any).
    public static func service(forUsageDescriptionKey key: String) -> String? {
        usageKeyToService[key]
    }

    private static let entitlementToService: [String: String] = [
        "com.apple.security.device.camera": "kTCCServiceCamera",
        "com.apple.security.device.microphone": "kTCCServiceMicrophone",
        "com.apple.security.device.audio-input": "kTCCServiceMicrophone",
        "com.apple.security.device.bluetooth": "kTCCServiceBluetoothAlways",
        "com.apple.security.personal-information.addressbook": "kTCCServiceAddressBook",
        "com.apple.security.personal-information.calendars": "kTCCServiceCalendar",
        "com.apple.security.personal-information.location": "kTCCServiceLocation",
        "com.apple.security.personal-information.photos-library": "kTCCServicePhotos",
        "com.apple.security.automation.apple-events": "kTCCServiceAppleEvents",
    ]

    private static let usageKeyToService: [String: String] = [
        "NSCameraUsageDescription": "kTCCServiceCamera",
        "NSMicrophoneUsageDescription": "kTCCServiceMicrophone",
        "NSAudioCaptureUsageDescription": "kTCCServiceAudioCapture",
        "NSContactsUsageDescription": "kTCCServiceAddressBook",
        "NSCalendarsUsageDescription": "kTCCServiceCalendar",
        "NSCalendarsFullAccessUsageDescription": "kTCCServiceCalendar",
        "NSCalendarsWriteOnlyAccessUsageDescription": "kTCCServiceCalendar",
        "NSRemindersUsageDescription": "kTCCServiceReminders",
        "NSRemindersFullAccessUsageDescription": "kTCCServiceReminders",
        "NSPhotoLibraryUsageDescription": "kTCCServicePhotos",
        "NSPhotoLibraryAddUsageDescription": "kTCCServicePhotosAdd",
        "NSLocationUsageDescription": "kTCCServiceLocation",
        "NSLocationWhenInUseUsageDescription": "kTCCServiceLocation",
        "NSLocationAlwaysUsageDescription": "kTCCServiceLocation",
        "NSLocationAlwaysAndWhenInUseUsageDescription": "kTCCServiceLocation",
        "NSAppleEventsUsageDescription": "kTCCServiceAppleEvents",
        "NSBluetoothAlwaysUsageDescription": "kTCCServiceBluetoothAlways",
        "NSBluetoothPeripheralUsageDescription": "kTCCServiceBluetoothAlways",
        "NSBluetoothWhileInUseUsageDescription": "kTCCServiceBluetoothAlways",
        "NSSpeechRecognitionUsageDescription": "kTCCServiceSpeechRecognition",
        "NSSiriUsageDescription": "kTCCServiceSiri",
        "NSUserTrackingUsageDescription": "kTCCServiceUserTracking",
        "NSMotionUsageDescription": "kTCCServiceMotion",
        "NSNearbyInteractionUsageDescription": "kTCCServiceNearbyInteraction",
        "NSFaceIDUsageDescription": "kTCCServiceFaceID",
        "NSScreenCaptureUsageDescription": "kTCCServiceScreenCapture",
        "NSDesktopFolderUsageDescription": "kTCCServiceSystemPolicyDesktopFolder",
        "NSDocumentsFolderUsageDescription": "kTCCServiceSystemPolicyDocumentsFolder",
        "NSDownloadsFolderUsageDescription": "kTCCServiceSystemPolicyDownloadsFolder",
        "NSRemovableVolumesUsageDescription": "kTCCServiceSystemPolicyRemovableVolumes",
        "NSNetworkVolumesUsageDescription": "kTCCServiceSystemPolicyNetworkVolumes",
    ]

    /// A friendly name for an `NS…UsageDescription` key, independent of TCC.
    public static func friendlyName(forUsageDescriptionKey key: String) -> String {
        if let service = usageKeyToService[key] {
            return friendlyName(for: service)
        }
        // Derive from the key: NSFooBarUsageDescription -> "Foo Bar"
        var stripped = key
        if stripped.hasPrefix("NS") { stripped.removeFirst(2) }
        for suffix in ["UsageDescription", "Usage"] where stripped.hasSuffix(suffix) {
            stripped.removeLast(suffix.count)
        }
        var result = ""
        for (index, char) in stripped.enumerated() {
            if index > 0, char.isUppercase { result.append(" ") }
            result.append(char)
        }
        return result.isEmpty ? key : result
    }
}
