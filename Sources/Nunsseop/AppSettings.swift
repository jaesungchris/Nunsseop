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
    /// Whether the notch shows on external displays while the MacBook lid is closed.
    @Published var showInClamshell: Bool { didSet { defaults.set(showInClamshell, forKey: "showInClamshell") } }
    @Published var checkForUpdates: Bool { didSet { defaults.set(checkForUpdates, forKey: "checkForUpdates") } }
    @Published var batteryAlerts: Bool { didSet { defaults.set(batteryAlerts, forKey: "batteryAlerts") } }
    @Published var capsLockHUD: Bool { didSet { defaults.set(capsLockHUD, forKey: "capsLockHUD") } }
    @Published var screenshotsToShelf: Bool { didSet { defaults.set(screenshotsToShelf, forKey: "screenshotsToShelf") } }
    @Published var localNotifications: Bool { didSet { defaults.set(localNotifications, forKey: "localNotifications") } }
    @Published var timerTab: Bool { didSet { defaults.set(timerTab, forKey: "timerTab") } }
    @Published var shelfTab: Bool { didSet { defaults.set(shelfTab, forKey: "shelfTab") } }
    @Published var searchTab: Bool { didSet { defaults.set(searchTab, forKey: "searchTab") } }
    @Published var emojiTab: Bool { didSet { defaults.set(emojiTab, forKey: "emojiTab") } }
    @Published var aiTab: Bool { didSet { defaults.set(aiTab, forKey: "aiTab") } }
    /// Grows the expanded notch past its set width, as far as the screen allows, so every tab fits.
    @Published var widenForTabs: Bool { didSet { defaults.set(widenForTabs, forKey: "widenForTabs") } }
    /// A system-wide shortcut opens the Search tab from anywhere.
    @Published var searchHotkey: Bool { didSet { defaults.set(searchHotkey, forKey: "searchHotkey") } }
    @Published var searchHotKey: HotKeyCombo {
        didSet {
            defaults.set(Int(searchHotKey.keyCode), forKey: "searchHotKeyCode")
            defaults.set(Int(searchHotKey.modifiers), forKey: "searchHotKeyModifiers")
            defaults.set(searchHotKey.key, forKey: "searchHotKeyName")
        }
    }
    /// Set when another app already holds the chosen shortcut.
    @Published var searchShortcutTaken = false
    /// While a new shortcut is being recorded the current one is released.
    @Published var recordingShortcut = false
    @Published var peripheralBatteries: Bool { didSet { defaults.set(peripheralBatteries, forKey: "peripheralBatteries") } }
    /// Shows when any app uses the camera or microphone.
    @Published var privacyIndicator: Bool { didSet { defaults.set(privacyIndicator, forKey: "privacyIndicator") } }
    @Published var recordAudio: Bool { didSet { defaults.set(recordAudio, forKey: "recordAudio") } }
    /// Order of the tabs after Home, as NotchTab raw values.
    @Published var tabOrder: [String] { didSet { defaults.set(tabOrder, forKey: "tabOrder") } }
    @Published var headerDate: Bool { didSet { defaults.set(headerDate, forKey: "headerDate") } }
    @Published var headerWeather: Bool { didSet { defaults.set(headerWeather, forKey: "headerWeather") } }
    @Published var collapsedMusic: Bool { didSet { defaults.set(collapsedMusic, forKey: "collapsedMusic") } }
    @Published var collapsedTimer: Bool { didSet { defaults.set(collapsedTimer, forKey: "collapsedTimer") } }
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
            "shelfTab": true,
            "searchTab": true,
            "emojiTab": true,
            "aiTab": true,
            "widenForTabs": true,
            "searchHotkey": true,
            "peripheralBatteries": true,
            "privacyIndicator": true,
            "recordAudio": false,
            "tabOrder": NotchTab.allCases.filter { $0 != .home }.map(\.rawValue),
            "headerDate": true,
            "headerWeather": true,
            "collapsedMusic": true,
            "collapsedTimer": true,
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
            "showInClamshell": true,
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
        shelfTab = defaults.bool(forKey: "shelfTab")
        searchTab = defaults.bool(forKey: "searchTab")
        emojiTab = defaults.bool(forKey: "emojiTab")
        aiTab = defaults.bool(forKey: "aiTab")
        widenForTabs = defaults.bool(forKey: "widenForTabs")
        searchHotkey = defaults.bool(forKey: "searchHotkey")
        if let name = defaults.string(forKey: "searchHotKeyName") {
            searchHotKey = HotKeyCombo(keyCode: UInt32(defaults.integer(forKey: "searchHotKeyCode")),
                                       modifiers: UInt32(defaults.integer(forKey: "searchHotKeyModifiers")), key: name)
        } else {
            searchHotKey = .defaultSearch
        }
        peripheralBatteries = defaults.bool(forKey: "peripheralBatteries")
        privacyIndicator = defaults.bool(forKey: "privacyIndicator")
        recordAudio = defaults.bool(forKey: "recordAudio")
        tabOrder = defaults.stringArray(forKey: "tabOrder") ?? []
        headerDate = defaults.bool(forKey: "headerDate")
        headerWeather = defaults.bool(forKey: "headerWeather")
        collapsedMusic = defaults.bool(forKey: "collapsedMusic")
        collapsedTimer = defaults.bool(forKey: "collapsedTimer")
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
        showInClamshell = defaults.bool(forKey: "showInClamshell")
        mirrorCameraID = defaults.string(forKey: "mirrorCameraID") ?? ""
        swipeToOpen = defaults.bool(forKey: "swipeToOpen")
        swipeForTracks = defaults.bool(forKey: "swipeForTracks")
    }

    /// Every tab after Home in the user's order, including tabs added in newer versions.
    var orderedTabs: [NotchTab] {
        let saved = tabOrder.compactMap(NotchTab.init(rawValue:)).filter { $0 != .home }
        let missing = NotchTab.allCases.filter { $0 != .home && !saved.contains($0) }
        return saved + missing
    }

    var visibleTabs: [NotchTab] { [.home] + orderedTabs.filter(isVisible) }

    func isVisible(_ tab: NotchTab) -> Bool {
        switch tab {
        case .home: return true
        case .shelf: return shelfTab
        case .timer: return timerTab
        case .clipboard: return clipboardTab
        case .notes: return notesTab
        case .tools: return toolsTab
        case .system: return systemTab
        case .apps: return appsTab
        case .search: return searchTab
        case .emoji: return emojiTab
        case .ai: return aiTab
        case .mirror: return mirrorEnabled
        }
    }

    func setVisible(_ tab: NotchTab, _ visible: Bool) {
        switch tab {
        case .home: break
        case .shelf: shelfTab = visible
        case .timer: timerTab = visible
        case .clipboard: clipboardTab = visible
        case .notes: notesTab = visible
        case .tools: toolsTab = visible
        case .system: systemTab = visible
        case .apps: appsTab = visible
        case .search: searchTab = visible
        case .emoji: emojiTab = visible
        case .ai: aiTab = visible
        case .mirror: mirrorEnabled = visible
        }
    }

    func moveTab(_ tab: NotchTab, by offset: Int) {
        var order = orderedTabs
        guard let index = order.firstIndex(of: tab) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        tabOrder = order.map(\.rawValue)
    }

    func resetSizes() {
        expandedWidth = 620
        expandedHeight = 196
        pillWidth = 190
        compactLiveActivity = false
    }
}
