import SwiftUI

extension Color {
    /// Initialize Color with a hex value like 0xRRGGBB and optional alpha
    init(hex: UInt, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue, opacity: alpha)
    }
    
    
    /// Brand primary green: #08FF00
    static var brandPrimary: Color { Color(hex: 0x08FF00) }

    /// Slightly darker brand green for gradients: ~#06CC00
    static var brandPrimaryDark: Color { Color(hex: 0x06CC00) }

    /// AI bubble pink: #EFD5EE
    static var aiBubblePink: Color { Color(hex: 0xEFD5EE) }
    
    // MARK: - Onboarding Card Colors
    /// Bright green for cards: #16FF0F
    static var brandBrightGreen: Color { Color(hex: 0x16FF0F) }
    
    /// Light purple for cards: #DCEAF7
    static var brandLightPurple: Color { Color(hex: 0xDCEAF7) }
    
    /// Bright cyan for cards: #0FA3FF
    static var brandBrightCyan: Color { Color(hex: 0x0FA3FF) }
    
    /// Bright magenta for cards: #FF0FF3
    static var brandBrightMagenta: Color { Color(hex: 0xFF0FF3) }
    
    /// Bright red for cards: #FF1F0F
    static var brandBrightRed: Color { Color(hex: 0xFF1F0F) }
    
    /// Bright purple for cards: #830FFF
    static var brandBrightPurple: Color { Color(hex: 0x830FFF) }
    
    /// Current day color for calendar: #0E0B95
    static var brandCurrentDay: Color { Color(hex: 0x0E0B95) }
    
    /// Premium user color: #110F7D
    static var brandPremium: Color { Color(hex: 0x110F7D) }
}


