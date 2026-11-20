import Foundation

// App-level choices shared by the HUD and shortcut feedback.
enum HUDAccessibility {
    // The old Animation checkbox stored the inverse choice. Keep its key so
    // existing users retain their preference when it moves into Accessibility.
    static var reduceMotion: Bool {
        get { reduceMotion(in: .standard) }
        set { UserDefaults.standard.set(!newValue, forKey: "hud.autoHide.animated") }
    }

    static func reduceMotion(in store: UserDefaults) -> Bool {
        !(store.object(forKey: "hud.autoHide.animated") as? Bool ?? true)
    }

    static let reduceTransparencyDidChange = Notification.Name("PerformanceHUD.reduceTransparencyDidChange")

    static var reduceTransparency: Bool {
        get { UserDefaults.standard.bool(forKey: "hud.accessibility.reduceTransparency") }
        set {
            UserDefaults.standard.set(newValue, forKey: "hud.accessibility.reduceTransparency")
            NotificationCenter.default.post(name: reduceTransparencyDidChange, object: nil)
        }
    }
}
