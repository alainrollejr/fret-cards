import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum Theme {
    static let accent = dynamic(light: (0x2C, 0x5F, 0x8F), dark: (0x7E, 0xAE, 0xDC))
    static let good = dynamic(light: (0x1D, 0x82, 0x48), dark: (0x45, 0xC2, 0x7A))
    static let bad = dynamic(light: (0xC0, 0x35, 0x2D), dark: (0xFF, 0x6F, 0x63))
    static let inlay = dynamic(light: (0xC3, 0xCB, 0xD4), dark: (0x3A, 0x44, 0x4F))
    static let musicFont = "NotoMusic-Regular"

    private static func dynamic(light: (Int, Int, Int), dark: (Int, Int, Int)) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
        })
        #else
        return Color(red: Double(light.0) / 255, green: Double(light.1) / 255, blue: Double(light.2) / 255)
        #endif
    }
}
