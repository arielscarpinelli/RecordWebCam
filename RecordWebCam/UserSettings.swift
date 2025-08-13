import Foundation

struct UserSettings {

    private enum Keys {
        static let saveToCameraRoll = "saveToCameraRoll"
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
}
