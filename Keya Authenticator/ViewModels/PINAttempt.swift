import Foundation

@Observable
final class PINAttempt {
    private(set) var message: String?
    private(set) var failureCount = 0
    private(set) var lockoutSecondsRemaining: Int?

    private let authenticationManager: AuthenticationManager
    private var countdown: Task<Void, Never>?

    init(authenticationManager: AuthenticationManager) {
        self.authenticationManager = authenticationManager
    }

    func submit(_ pin: String) -> AuthenticationManager.PINAuthResult? {
        message = nil
        do {
            let result = try authenticationManager.authenticateWithPIN(pin)
            stopCountdown()
            return result
        } catch let error as AuthenticationManager.AuthenticationError {
            failureCount += 1
            if showLockoutIfActive() {
                return nil
            }
            if case .invalidPIN = error, let lockout = authenticationManager.lockoutAfterNextFailure() {
                message = Self.warning(before: lockout)
            } else {
                message = error.localizedDescription
            }
        } catch {
            failureCount += 1
            message = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "PIN verification failed. Please try again.")
        }
        return nil
    }

    @discardableResult
    func showLockoutIfActive() -> Bool {
        guard let seconds = authenticationManager.pinLockoutSecondsRemaining(), seconds > 0 else { return false }
        lockoutSecondsRemaining = seconds
        message = AuthenticationManager.lockoutMessage(seconds: seconds)
        countdown?.cancel()
        countdown = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, let current = lockoutSecondsRemaining else { return }
                let remaining = current - 1
                if remaining > 0 {
                    lockoutSecondsRemaining = remaining
                    message = AuthenticationManager.lockoutMessage(seconds: remaining)
                } else {
                    stopCountdown()
                    message = authenticationManager.lockoutAfterNextFailure().map(Self.warning(before:))
                    return
                }
            }
        }
        return true
    }

    func clearMessage() {
        message = nil
    }

    private func stopCountdown() {
        countdown?.cancel()
        countdown = nil
        lockoutSecondsRemaining = nil
    }

    private static func warning(before lockout: TimeInterval) -> String {
        let seconds = Int(lockout)
        if seconds >= 60 {
            return String(localized: "Incorrect PIN. One more wrong PIN locks entry for \(seconds / 60) minutes.")
        }
        return String(localized: "Incorrect PIN. One more wrong PIN locks entry for \(seconds) seconds.")
    }
}
