import SwiftUI

struct TokenRowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        return Self.fallbackPalette[abs(key.hashValue) % Self.fallbackPalette.count]
    }

    private var monogram: String {
        let src = displayIssuer ?? token.name
        let words = src.split(separator: " ")
        return words.count >= 2
            ? String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
            : String(src.prefix(2)).uppercased()
    }

    @ViewBuilder
    private var avatarView: some View {
        if let assetName = serviceInfo?.assetName,
           let uiImage = UIImage(named: assetName)
        {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .background(Color(.systemBackground))
        } else {
            Text(monogram)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(avatarColors.fg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(avatarColors.bg)
        }
    }

    private var avatarSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 40 : 32
    }

    // MARK: - Code helpers

    private var codeVisible: Bool {
        !settings.hideCodesByDefault || isRevealed
    }

    private func currentCode(at t: Date) -> String? {
        try? token.generateCode(time: t)
    }

    private func nextCode(at t: Date) -> String? {
        guard token.type == .totp, let period = token.period else { return nil }
        return try? token.generateCode(time: t.addingTimeInterval(Double(period)))
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

            VStack(alignment: .leading, spacing: 4) {
                nameRow
                if token.type == .totp { progressBar(progress: animatedProgress) }
                codeRow(at: t)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 6 : 2)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .onChange(of: currentCode(at: t)) { _, _ in
            if settings.hideCodesByDefault { cancelRehide()
                isRevealed = false
            }
        }
        .onChange(of: totpProgress(at: t)) { _, newVal in
            // Detect a period rollover: progress jumped backward (e.g. 0.98 → 0.01).
            // In that case snap without animation to avoid a reverse-sweep glitch.
            // A forward jump larger than ~2 s (app was backgrounded) also snaps so
            // the bar doesn't animate a long catch-up sweep.
            let forwardLeap = newVal - animatedProgress
            let periodSeconds = Double(token.period ?? 30)
            if newVal < animatedProgress - 0.05 || forwardLeap > (2.0 / periodSeconds) {
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
        .accessibilityHint("Tap to copy")
        .onTapGesture {
            if !codeVisible {
                // First tap reveals the code — don't copy until the user taps again.
                withAnimation(.spring(duration: 0.25)) { isRevealed = true }
                if settings.hideCodesByDefault { scheduleRehide() }
            } else {
                if settings.hideCodesByDefault { scheduleRehide() }
                onCopy?()
            }
        }
        .onAppear {
            isRevealed = !settings.hideCodesByDefault
            animatedProgress = totpProgress(at: clock.now)
        }
        .onChange(of: settings.hideCodesByDefault) { _, v in
            if v { cancelRehide()
                isRevealed = false
            }
        }
    }

    // MARK: - Name row

    private var nameRow: some View {
        HStack(spacing: 5) {
            if let issuer = displayIssuer,
               issuer.lowercased() != token.name.lowercased()
            {
                Text(issuer)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(token.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(token.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            if isNew {
                Text("New")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color.green)
                    .clipShape(Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Progress bar

    private func progressBarColor(progress: Double) -> Color {
        let remaining = 1.0 - progress
        if remaining < 0.15 { return .red }
        if remaining < 0.30 { return .orange }
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

    private func codeRow(at t: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if codeVisible {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Current code
                    Group {
                        if let code = currentCode(at: t) {
                            Text(formatCode(code))
                                .contentTransition(.numericText())
                                .accessibilityLabel("Authentication code")
                                .accessibilityValue("")
                                .accessibilityHint(codeVisible ? "Double-tap to copy" : "")
                        } else {
                            Text(token.digits == 6 ? "••• •••" : "•••• ••••")
                                .foregroundStyle(.quaternary)
                                .accessibilityHidden(true)
                        }
                    }
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                    .tracking(1)
                    .foregroundStyle(.primary)

                    if totpProgress(at: t) > 0.80, let next = nextCode(at: t) {
                        HStack(spacing: 7) {
                            Text("Next", comment: "Label for the upcoming OTP code")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(formatCode(next))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                        .accessibilityHidden(true)
                    }
                }
            } else {
                Text(token.digits == 6 ? "••• •••" : "•••• ••••")
                    .font(.system(.title2, design: .monospaced).weight(.medium))
                    .foregroundStyle(.quaternary)
                    .accessibilityLabel("Tap to reveal code")
                    .accessibilityHint("Tap to reveal your authentication code")
                    .accessibilityAddTraits(.isButton)
            }

            Spacer(minLength: 6)

            if token.type == .hotp { refreshButton }
        }
    }

    // MARK: - HOTP refresh button

    private var refreshButton: some View {
        Button {
            onCounterIncrement?()
            ClipboardManager.shared.provideHapticFeedback(.medium)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 28, height: 28)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Generate next code")
    }

    // MARK: - Helpers

    private func formatCode(_ code: String) -> String {
        if code.count == 6 { let i = code.index(code.startIndex, offsetBy: 3)
            return "\(code[..<i]) \(code[i...])"
        }
        if code.count == 8 { let i = code.index(code.startIndex, offsetBy: 4)
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
