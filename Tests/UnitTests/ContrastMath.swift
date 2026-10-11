import SwiftUI
import UIKit
import XCTest

enum ContrastMath {
    private static func components(_ color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return (red, green, blue, alpha)
    }

    private static func luminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    static func ratio(_ foreground: Color, over background: Color) -> CGFloat {
        let back = components(background)
        let front = components(foreground)
        let mix = { (top: CGFloat, bottom: CGFloat) in top * front.alpha + bottom * (1 - front.alpha) }
        let textLuminance = luminance(
            red: mix(front.red, back.red), green: mix(front.green, back.green), blue: mix(front.blue, back.blue)
        )
        let backLuminance = luminance(red: back.red, green: back.green, blue: back.blue)
        return (max(textLuminance, backLuminance) + 0.05) / (min(textLuminance, backLuminance) + 0.05)
    }
}
