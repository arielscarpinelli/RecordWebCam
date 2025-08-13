import Foundation

struct UserSettings {

    private enum Keys {
        static let saveToCameraRoll = "saveToCameraRoll"
        static let forceLandscapeStart = "forceLandscapeStart"
    }

    static var saveToCameraRoll: Bool {
        get {
            // Default to true if the value is not yet set
            return UserDefaults.standard.object(forKey: Keys.saveToCameraRoll) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.saveToCameraRoll)
        }
    }

    static var forceLandscapeStart: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Keys.forceLandscapeStart)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.forceLandscapeStart)
        }
    }
}
