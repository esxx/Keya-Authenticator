import Foundation

nonisolated enum BiometricChangeNotice: Equatable {
    case changed
    case unavailable

    init(biometricsAvailable: Bool) {
        self = biometricsAvailable ? .changed : .unavailable
    }

    var title: String {
        switch self {
        case .changed: String(localized: "Biometric database changed")
        case .unavailable: String(localized: "Biometric unlock turned off")
        }
    }

    var message: String {
        switch self {
        case .changed:
            String(
                localized: "The Face ID / Touch ID database on this device has changed since your last login. Biometric unlock has been disabled as a security precaution. You can re-enable it in Settings → App lock once you've confirmed the change was made by you."
            )
        case .unavailable:
            String(
                localized: "Biometric unlock has been turned off, so Keya can't use Face ID or Touch ID right now. To use it again, make sure it is set up and allowed for Keya in iOS Settings → Face ID & Passcode → Other Apps, then turn it on in Keya's Settings → App lock."
            )
        }
    }
}
