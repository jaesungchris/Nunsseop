import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    nonisolated static let expandedWidthRange: ClosedRange<Double> = 520...780
    nonisolated static let expandedHeightRange: ClosedRange<Double> = 170...260
    nonisolated static let pillWidthRange: ClosedRange<Double> = 140...320

    private let defaults = UserDefaults.standard

    @Published var expandedWidth: Double { didSet { defaults.set(expandedWidth, forKey: "expandedWidth") } }
    @Published var expandedHeight: Double { didSet { defaults.set(expandedHeight, forKey: "expandedHeight") } }
    /// Width of the collapsed shape on screens without a camera housing.
    @Published var pillWidth: Double { didSet { defaults.set(pillWidth, forKey: "pillWidth") } }
    /// Smaller artwork/visualizer "ears" beside the collapsed notch while music plays.
    @Published var compactLiveActivity: Bool { didSet { defaults.set(compactLiveActivity, forKey: "compactLiveActivity") } }

    /// Shows title and artist under the collapsed notch when the track or play state changes.
    @Published var sneakPeekEnabled: Bool { didSet { defaults.set(sneakPeekEnabled, forKey: "sneakPeekEnabled") } }
    @Published var sneakPeekAlways: Bool { didSet { defaults.set(sneakPeekAlways, forKey: "sneakPeekAlways") } }
    @Published var sneakPeekDuration: Double { didSet { defaults.set(sneakPeekDuration, forKey: "sneakPeekDuration") } }
    /// Seconds the pointer must rest on the notch before it opens.
    @Published var openDelay: Double { didSet { defaults.set(openDelay, forKey: "openDelay") } }

    @Published var volumeHUDEnabled: Bool { didSet { defaults.set(volumeHUDEnabled, forKey: "volumeHUDEnabled") } }
    /// Takes over the volume/brightness keys so only the notch HUD shows.
    @Published var replaceSystemHUD: Bool { didSet { defaults.set(replaceSystemHUD, forKey: "replaceSystemHUD") } }
    @Published var batteryInHeader: Bool { didSet { defaults.set(batteryInHeader, forKey: "batteryInHeader") } }
    @Published var chargingHUDEnabled: Bool { didSet { defaults.set(chargingHUDEnabled, forKey: "chargingHUDEnabled") } }
    @Published var headphoneHUDEnabled: Bool { didSet { defaults.set(headphoneHUDEnabled, forKey: "headphoneHUDEnabled") } }
    @Published var calendarEnabled: Bool { didSet { defaults.set(calendarEnabled, forKey: "calendarEnabled") } }
    @Published var remindersEnabled: Bool { didSet { defaults.set(remindersEnabled, forKey: "remindersEnabled") } }
    /// NSScreen.localizedName of the display to use; empty means automatic.
    @Published var displayName: String { didSet { defaults.set(displayName, forKey: "displayName") } }
    @Published var checkForUpdates: Bool { didSet { defaults.set(checkForUpdates, forKey: "checkForUpdates") } }
    @Published var batteryAlerts: Bool { didSet { defaults.set(batteryAlerts, forKey: "batteryAlerts") } }
    @Published var capsLockHUD: Bool { didSet { defaults.set(capsLockHUD, forKey: "capsLockHUD") } }
    @Published var screenshotsToShelf: Bool { didSet { defaults.set(screenshotsToShelf, forKey: "screenshotsToShelf") } }
    @Published var localNotifications: Bool { didSet { defaults.set(localNotifications, forKey: "localNotifications") } }
    @Published var timerTab: Bool { didSet { defaults.set(timerTab, forKey: "timerTab") } }
    @Published var systemTab: Bool { didSet { defaults.set(systemTab, forKey: "systemTab") } }
    @Published var appsTab: Bool { didSet { defaults.set(appsTab, forKey: "appsTab") } }
    @Published var lyricsEnabled: Bool { didSet { defaults.set(lyricsEnabled, forKey: "lyricsEnabled") } }
    /// Keeps the current lyric line under the notch while music plays.
    @Published var lyricsUnderNotch: Bool { didSet { defaults.set(lyricsUnderNotch, forKey: "lyricsUnderNotch") } }
    /// City for the header weather chip; empty hides it.
    @Published var weatherCity: String { didSet { defaults.set(weatherCity, forKey: "weatherCity") } }
    @Published var downloadAlerts: Bool { didSet { defaults.set(downloadAlerts, forKey: "downloadAlerts") } }
    @Published var downloadsToShelf: Bool { didSet { defaults.set(downloadsToShelf, forKey: "downloadsToShelf") } }
    /// Also controls whether copied text is recorded at all.
    @Published var clipboardTab: Bool { didSet { defaults.set(clipboardTab, forKey: "clipboardTab") } }
    @Published var notesTab: Bool { didSet { defaults.set(notesTab, forKey: "notesTab") } }
    @Published var toolsTab: Bool { didSet { defaults.set(toolsTab, forKey: "toolsTab") } }
    @Published var mirrorEnabled: Bool { didSet { defaults.set(mirrorEnabled, forKey: "mirrorEnabled") } }
    /// AVCaptureDevice.uniqueID; empty means the system default camera.
    @Published var mirrorCameraID: String { didSet { defaults.set(mirrorCameraID, forKey: "mirrorCameraID") } }
    /// Two-finger swipe down on the notch opens it, swipe up closes it.
    @Published var swipeToOpen: Bool { didSet { defaults.set(swipeToOpen, forKey: "swipeToOpen") } }
    /// Two-finger swipe left/right on the Home tab skips tracks.
    @Published var swipeForTracks: Bool { didSet { defaults.set(swipeForTracks, forKey: "swipeForTracks") } }

    private init() {
        defaults.register(defaults: [
            "expandedWidth": 620.0,
            "expandedHeight": 196.0,
            "pillWidth": 190.0,
            "compactLiveActivity": false,
            "sneakPeekEnabled": true,
            "sneakPeekAlways": false,
            "sneakPeekDuration": 3.0,
            "openDelay": 0.1,
            "volumeHUDEnabled": true,
            "replaceSystemHUD": false,
            "batteryInHeader": true,
            "chargingHUDEnabled": true,
            "headphoneHUDEnabled": true,
            "calendarEnabled": true,
            "remindersEnabled": true,
            "mirrorEnabled": true,
            "timerTab": true,
            "systemTab": true,
            "appsTab": true,
            "lyricsEnabled": true,
            "lyricsUnderNotch": false,
            "weatherCity": "",
            "downloadAlerts": true,
            "downloadsToShelf": false,
            "batteryAlerts": true,
            "capsLockHUD": true,
            "screenshotsToShelf": true,
            "localNotifications": true,
            "clipboardTab": true,
            "notesTab": true,
            "toolsTab": true,
            "checkForUpdates": true,
            "displayName": "",
            "mirrorCameraID": "",
            "swipeToOpen": true,
            "swipeForTracks": true,
        ])
        expandedWidth = defaults.double(forKey: "expandedWidth")
        expandedHeight = defaults.double(forKey: "expandedHeight")
        pillWidth = defaults.double(forKey: "pillWidth")
        compactLiveActivity = defaults.bool(forKey: "compactLiveActivity")
        sneakPeekEnabled = defaults.bool(forKey: "sneakPeekEnabled")
        sneakPeekAlways = defaults.bool(forKey: "sneakPeekAlways")
        sneakPeekDuration = defaults.double(forKey: "sneakPeekDuration")
        openDelay = defaults.double(forKey: "openDelay")
        volumeHUDEnabled = defaults.bool(forKey: "volumeHUDEnabled")
        replaceSystemHUD = defaults.bool(forKey: "replaceSystemHUD")
        batteryInHeader = defaults.bool(forKey: "batteryInHeader")
        chargingHUDEnabled = defaults.bool(forKey: "chargingHUDEnabled")
        headphoneHUDEnabled = defaults.bool(forKey: "headphoneHUDEnabled")
        calendarEnabled = defaults.bool(forKey: "calendarEnabled")
        remindersEnabled = defaults.bool(forKey: "remindersEnabled")
        mirrorEnabled = defaults.bool(forKey: "mirrorEnabled")
        timerTab = defaults.bool(forKey: "timerTab")
        systemTab = defaults.bool(forKey: "systemTab")
        appsTab = defaults.bool(forKey: "appsTab")
        lyricsEnabled = defaults.bool(forKey: "lyricsEnabled")
        lyricsUnderNotch = defaults.bool(forKey: "lyricsUnderNotch")
        weatherCity = defaults.string(forKey: "weatherCity") ?? ""
        downloadAlerts = defaults.bool(forKey: "downloadAlerts")
        downloadsToShelf = defaults.bool(forKey: "downloadsToShelf")
        batteryAlerts = defaults.bool(forKey: "batteryAlerts")
        capsLockHUD = defaults.bool(forKey: "capsLockHUD")
        screenshotsToShelf = defaults.bool(forKey: "screenshotsToShelf")
        localNotifications = defaults.bool(forKey: "localNotifications")
        clipboardTab = defaults.bool(forKey: "clipboardTab")
        notesTab = defaults.bool(forKey: "notesTab")
        toolsTab = defaults.bool(forKey: "toolsTab")
        checkForUpdates = defaults.bool(forKey: "checkForUpdates")
        displayName = defaults.string(forKey: "displayName") ?? ""
        mirrorCameraID = defaults.string(forKey: "mirrorCameraID") ?? ""
        swipeToOpen = defaults.bool(forKey: "swipeToOpen")
        swipeForTracks = defaults.bool(forKey: "swipeForTracks")
    }

    func resetSizes() {
        expandedWidth = 620
        expandedHeight = 196
        pillWidth = 190
        compactLiveActivity = false
    }
}
