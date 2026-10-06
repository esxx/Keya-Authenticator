import SwiftUI

struct PINEntryView: View {
    @Binding var pin: String
    @Binding var isFocused: Bool
    var errorMessage: String?
    var shakeTrigger: Int
    let onComplete: () -> Void

    @State private var shakeOffset: CGFloat = 0

    private let length = AuthenticationManager.pinLength

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ForEach(0 ..< length, id: \.self) { i in
                    Circle()
                        .fill(i < pin.count ? Color.primary : Color.clear)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(i < pin.count ? Color.primary : Color(.separator), lineWidth: 1.5))
                }
            }
            .offset(x: shakeOffset)
            .padding(.bottom, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "PIN entry dots"))
            .accessibilityValue(String(localized: "\(pin.count) of \(length) digits entered"))

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .transition(.opacity)
                    .padding(.bottom, 4)
            }

            SecurePINField(text: $pin, isFocused: $isFocused)
                .opacity(0.001)
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }
        .onChange(of: pin) { _, newValue in
            let filtered = String(newValue.filter(\.isNumber).prefix(length))
            if filtered != newValue {
                pin = filtered
                return
            }
            if filtered.count == length {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onComplete() }
            }
        }
        .onChange(of: shakeTrigger) { _, _ in shake() }
    }

    private func shake() {
        withAnimation(.default) { shakeOffset = 10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(.default) { shakeOffset = -10 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.default) { shakeOffset = 6 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.default) { shakeOffset = 0 } }
    }
}
