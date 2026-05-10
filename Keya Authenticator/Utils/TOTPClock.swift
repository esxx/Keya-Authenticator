import Foundation

@Observable
final class TOTPClock {
    private(set) var now: Date = .now

    private var timer: Timer?

    init() {
        alignAndStart()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Private

    private func alignAndStart() {
        now = .now

        let t = Date.now.timeIntervalSince1970
        let delay = 1.0 - t.truncatingRemainder(dividingBy: 1.0)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            now = .now

            let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.now = .now
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }
}
