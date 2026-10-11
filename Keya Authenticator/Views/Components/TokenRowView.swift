import SwiftUI

struct TokenRowView: View {
    @ScaledMetric(relativeTo: .body) private var refreshBox: CGFloat = 28
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let token: Token
    @Bindable var settings: AppSettings
    var onEdit: (() -> Void)?
    var onExportQR: (() -> Void)?
    var onCounterIncrement: (() -> Void)?
    var onFavoriteToggle: (() -> Void)?
    var onCopy: (() -> Void)?
    var isNew: Bool = false

    @Environment(TOTPClock.self) private var clock

    @State private var isRevealed: Bool = false
    @State private var rehideTask: Task<Void, Never>? = nil
    @State private var animatedProgress: Double = 0

    // MARK: - Avatar

    private var displayIssuer: String? {
        ServiceIconResolver.displayIssuer(issuer: token.issuer, name: token.name)
    }

    private var serviceInfo: ServiceInfo? {
        ServiceIconResolver.resolve(issuer: token.issuer, name: token.name)
    }

    private static let fallbackPalette: [(bg: Color, fg: Color)] = [
        (Color(red: 0.90, green: 0.95, blue: 0.98), Color(red: 0.05, green: 0.27, blue: 0.49)),
        (Color(red: 0.93, green: 0.93, blue: 1.00), Color(red: 0.24, green: 0.20, blue: 0.54)),
        (Color(red: 0.88, green: 0.96, blue: 0.93), Color(red: 0.03, green: 0.31, blue: 0.25)),
        (Color(red: 0.98, green: 0.93, blue: 0.91), Color(red: 0.44, green: 0.17, blue: 0.07)),
        (Color(red: 0.98, green: 0.93, blue: 0.85), Color(red: 0.39, green: 0.22, blue: 0.02)),
        (Color(red: 0.92, green: 0.95, blue: 0.87), Color(red: 0.15, green: 0.31, blue: 0.04)),
        (Color(red: 0.98, green: 0.92, blue: 0.94), Color(red: 0.45, green: 0.14, blue: 0.24)),
        (Color(red: 0.95, green: 0.94, blue: 0.91), Color(red: 0.27, green: 0.27, blue: 0.25)),
    ]

    private var avatarColors: (bg: Color, fg: Color) {
        if let info = serviceInfo {
            return (info.brandColor, info.foregroundColor)
        }
        let key = displayIssuer ?? token.name
        return Self.fallbackPalette[Self.paletteIndex(for: key, count: Self.fallbackPalette.count)]
    }

    static func paletteIndex(for key: String, count: Int) -> Int {
        var hash: UInt = 0
        for scalar in key.unicodeScalars {
            hash = hash &* 31 &+ UInt(scalar.value)
        }
        return Int(hash % UInt(count))
    }

    private var monogram: String {
        let src = displayIssuer ?? token.name
        let words = src.split(separator: " ")
        return words.count >= 2
            ? String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
            : String(src.prefix(2)).uppercased()
    }

    private var avatarView: some View {
        Text(monogram)
            .font(.system(size: avatarSize * 12 / 32, weight: .semibold, design: .rounded))
            .foregroundColor(avatarColors.fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(avatarColors.bg)
    }

    private var avatarSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 40 : 32
    }

    // MARK: - Code helpers

    private var codeVisible: Bool {
        !settings.hideCodesByDefault || isRevealed
    }

    static func accessibilityCodeValue(code: String?, isVisible: Bool, secondsLeft: Int?) -> String {
        guard isVisible else { return String(localized: "Code hidden") }
        guard let code else { return "" }
        let digits = code.map(String.init).joined(separator: " ")
        guard let secondsLeft else { return digits }
        return "\(digits), \(String(localized: "\(secondsLeft) seconds left"))"
    }

    static func secondsLeftLabel(_ seconds: Int, locale: Locale = .current) -> String {
        Measurement(value: Double(seconds), unit: UnitDuration.seconds)
            .formatted(Measurement<UnitDuration>.FormatStyle(width: .narrow, locale: locale))
    }

    private func secondsLeft(at t: Date) -> Int? {
        guard token.type == .totp, let period = token.period else { return nil }
        let length = Double(period)
        return Int((length - t.timeIntervalSince1970.truncatingRemainder(dividingBy: length)).rounded(.up))
    }

    private func currentCode(at t: Date) -> String? {
        try? token.generateCode(time: t)
    }

    private func nextCode(at t: Date) -> String? {
        guard token.type == .totp, let period = token.period else { return nil }
        return try? token.generateCode(time: t.addingTimeInterval(Double(period)))
    }

    static func showsNextCode(at t: Date, period: Int) -> Bool {
        let length = Double(period)
        return length - t.timeIntervalSince1970.truncatingRemainder(dividingBy: length) <= 10
    }

    private func totpProgress(at t: Date) -> Double {
        guard token.type == .totp, let p = token.period else { return 0 }
        let ts = t.timeIntervalSince1970
        return (ts - floor(ts / Double(p)) * Double(p)) / Double(p)
    }

    // MARK: - Body

    var body: some View {
        let t = clock.now
        HStack(alignment: .center, spacing: 10) {
            avatarView
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(RoundedRectangle(cornerRadius: avatarSize * 0.25, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: avatarSize * 0.25, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 4) {
                nameRow
                if token.type == .totp {
                    progressBar(progress: animatedProgress)
                }
                codeRow(at: t)
            }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 6 : 2)
        .onChange(of: currentCode(at: t)) { _, _ in
            if settings.hideCodesByDefault {
                cancelRehide()
                isRevealed = false
            }
        }
        .onChange(of: totpProgress(at: t)) { _, newVal in
            let forwardLeap = newVal - animatedProgress
            let periodSeconds = Double(token.period ?? 30)
            if reduceMotion || newVal < animatedProgress - 0.05 || forwardLeap > (2.0 / periodSeconds) {
                animatedProgress = newVal
            } else {
                withAnimation(.linear(duration: 1)) { animatedProgress = newVal }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            let issuerPart = displayIssuer.map { "\($0), " } ?? ""
            return "\(issuerPart)\(token.name)"
        }())
        .accessibilityValue(Self.accessibilityCodeValue(
            code: currentCode(at: t),
            isVisible: codeVisible,
            secondsLeft: secondsLeft(at: t)
        ))
        .accessibilityHint(codeVisible ? "Tap to copy" : "Tap to reveal your authentication code")
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            if !codeVisible {
                withAnimation(.spring(duration: 0.25)) { isRevealed = true }
                if settings.hideCodesByDefault {
                    scheduleRehide()
                }
            } else {
                if settings.hideCodesByDefault {
                    scheduleRehide()
                }
                onCopy?()
            }
        }
        .onAppear {
            isRevealed = !settings.hideCodesByDefault
            animatedProgress = totpProgress(at: clock.now)
        }
        .onChange(of: settings.hideCodesByDefault) { _, v in
            if v {
                cancelRehide()
                isRevealed = false
            }
        }
    }

    // MARK: - Name row

    private var nameLineLimit: Int {
        dynamicTypeSize.isAccessibilitySize ? 2 : 1
    }

    private var nameLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 5))
    }

    private var nameRow: some View {
        nameLayout {
            if let issuer = displayIssuer,
               issuer.lowercased() != token.name.lowercased()
            {
                Text(issuer)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(nameLineLimit)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(token.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(nameLineLimit)
            } else {
                Text(token.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(nameLineLimit)
            }
            if isNew {
                Text("New")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Constants.Colors.confirmationGreen)
                    .clipShape(Capsule())
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Progress bar

    private func progressBarColor(progress: Double) -> Color {
        let remaining = 1.0 - progress
        if remaining < 0.15 {
            return .red
        }
        if remaining < 0.30 {
            return .orange
        }
        return .blue
    }

    private func progressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.separator).opacity(0.35))
                    .frame(height: 2)
                Capsule()
                    .fill(progressBarColor(progress: progress))
                    .frame(width: geo.size.width * CGFloat(1.0 - progress), height: 2)
            }
        }
        .frame(height: 2)
    }

    // MARK: - Code row

    private var codeLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    @ViewBuilder
    private func secondsLeftText(at t: Date) -> some View {
        if codeVisible, let secondsLeft = secondsLeft(at: t) {
            Text(Self.secondsLeftLabel(secondsLeft))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func codeRow(at t: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if codeVisible {
                codeLayout {
                    Group {
                        if let code = currentCode(at: t) {
                            Text(formatCode(code))
                                .contentTransition(reduceMotion ? .identity : .numericText())
                                .accessibilityHidden(true)
                        } else {
                            Text(token.digits == 6 ? "••• •••" : "•••• ••••")
                                .foregroundStyle(.quaternary)
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                    .tracking(1)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                    if let period = token.period, Self.showsNextCode(at: t, period: period),
                       let next = nextCode(at: t)
                    {
                        HStack(spacing: 7) {
                            Text("next", comment: "Label for the upcoming OTP code")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(formatCode(next))
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .contentTransition(reduceMotion ? .identity : .numericText())
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityHidden(true)
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        secondsLeftText(at: t)
                    }
                }
            } else {
                Text(token.digits == 6 ? "••• •••" : "•••• ••••")
                    .font(.system(.title2, design: .monospaced).weight(.medium))
                    .foregroundStyle(.quaternary)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 6)

            if !dynamicTypeSize.isAccessibilitySize {
                secondsLeftText(at: t)
            }

            if token.type == .hotp {
                refreshButton
            }
        }
    }

    // MARK: - HOTP refresh button

    private var refreshButton: some View {
        Button {
            onCounterIncrement?()
            ClipboardManager.shared.provideHapticFeedback(.medium)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: refreshBox * 13 / 28, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: refreshBox, height: refreshBox)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Generate next code")
    }

    // MARK: - Helpers

    private func formatCode(_ code: String) -> String {
        if code.count == 6 {
            let i = code.index(code.startIndex, offsetBy: 3)
            return "\(code[..<i]) \(code[i...])"
        }
        if code.count == 8 {
            let i = code.index(code.startIndex, offsetBy: 4)
            return "\(code[..<i]) \(code[i...])"
        }
        return code
    }

    private func scheduleRehide() {
        rehideTask?.cancel()
        rehideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) { isRevealed = false }
            }
        }
    }

    private func cancelRehide() {
        rehideTask?.cancel()
        rehideTask = nil
    }
}
