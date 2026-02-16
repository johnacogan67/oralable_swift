//
//  DesignSystem.swift
//  OralableApp
//
//  Centralized design system for consistent UI styling.
//
//  Components:
//  - Colors: Primary, secondary, background, text colors
//  - Typography: Font styles for different text elements
//  - Spacing: Standard spacing values (xs, sm, md, lg, xl)
//  - CornerRadius: Rounded corner sizes
//  - Shadows: Shadow definitions for elevation
//  - Layout: Device-specific layout constants
//
//  Usage:
//  - Injected as EnvironmentObject
//  - Access via: designSystem.colors.primary
//
//  Supports:
//  - Light/Dark mode adaptation
//  - iPad layout adjustments
//  - Dynamic Type scaling
//

import SwiftUI

// MARK: - Main Design System

class DesignSystem: ObservableObject {
    // Published properties for SwiftUI updates (lowercase - correct)
    @Published var colors: ColorSystem
    @Published var typography: TypographySystem
    @Published var spacing: SpacingSystem
    @Published var cornerRadius: CornerRadiusSystem

    // Uppercase aliases for backward compatibility (fixes your errors)
    var Colors: ColorSystem { colors }
    var Typography: TypographySystem { typography }
    var Spacing: SpacingSystem { spacing }
    var CornerRadius: CornerRadiusSystem { cornerRadius }
    var Sizing: SpacingSystem { spacing }  // Alias Sizing to spacing

    init() {
        self.colors = ColorSystem()
        self.typography = TypographySystem()
        self.spacing = SpacingSystem()
        self.cornerRadius = CornerRadiusSystem()
    }
}

// MARK: - Static Accessors (Stateless Systems Only)
extension DesignSystem {
    // Static accessors for stateless systems only
    static var Sizing: SizingSystem { SizingSystem() }
    static var Layout: LayoutSystem { LayoutSystem() }
    static var Shadow: ShadowSystem { ShadowSystem() }
    static var Animation: AnimationSystem { AnimationSystem() }
    static var sizing: SizingSystem { SizingSystem() }
}

// MARK: - Color System

struct ColorSystem {
    // Text Colors
    let textPrimary = Color("TextPrimary", bundle: nil)
    let textSecondary = Color("TextSecondary", bundle: nil)
    let textTertiary = Color("TextTertiary", bundle: nil)
    let textDisabled = Color("TextDisabled", bundle: nil)
    
    // Background Colors
    let backgroundPrimary = Color("BackgroundPrimary", bundle: nil)
    let backgroundSecondary = Color("BackgroundSecondary", bundle: nil)
    let backgroundTertiary = Color("BackgroundTertiary", bundle: nil)
    
    // Primary Colors
    let primaryBlack = Color("PrimaryBlack", bundle: nil)
    let primaryWhite = Color("PrimaryWhite", bundle: nil)
    
    // Grayscale
    let gray50 = Color("Gray50", bundle: nil)
    let gray100 = Color("Gray100", bundle: nil)
    let gray200 = Color("Gray200", bundle: nil)
    let gray300 = Color("Gray300", bundle: nil)
    let gray400 = Color("Gray400", bundle: nil)
    let gray500 = Color("Gray500", bundle: nil)
    let gray600 = Color("Gray600", bundle: nil)
    let gray700 = Color("Gray700", bundle: nil)
    let gray800 = Color("Gray800", bundle: nil)
    let gray900 = Color("Gray900", bundle: nil)
    
    // Interactive States
    let hover = Color("Hover", bundle: nil)
    let pressed = Color("Pressed", bundle: nil)
    let border = Color("Border", bundle: nil)
    let divider = Color("Divider", bundle: nil)
    
    // Semantic Colors
    let info = Color.blue
    let warning = Color.orange
    let error = Color.red
    let success = Color.green
    
    // Shadow color
    let shadow = Color.black.opacity(0.1)
}

// MARK: - Typography System

struct TypographySystem {
    // Dynamic Type relative text styles for accessibility scaling
    // Maps semantic roles to iOS text styles so fonts scale with user preferences

    // Headings
    var h1: Font { .system(.largeTitle, weight: .bold) }           // was 34pt bold
    var h2: Font { .system(.title, weight: .semibold) }            // was 28pt semibold
    var h3: Font { .system(.title2, weight: .semibold) }           // was 22pt semibold
    var h4: Font { .system(.headline, weight: .medium) }           // was 18pt medium

    // Large title and headline
    var largeTitle: Font { .system(.largeTitle, weight: .bold) }   // was 34pt bold
    var headline: Font { .system(.headline, weight: .semibold) }   // was 17pt semibold

    // Body variants
    var body: Font { .system(.body, weight: .regular) }            // was 16pt regular
    var bodyBold: Font { .system(.body, weight: .bold) }           // was 16pt bold
    var bodyMedium: Font { .system(.body, weight: .medium) }       // was 16pt medium
    var bodyLarge: Font { .system(.headline, weight: .regular) }   // was 18pt regular
    var bodySmall: Font { .system(.subheadline, weight: .regular) }// was 14pt regular

    // Label variants
    var labelLarge: Font { .system(.body, weight: .medium) }       // was 16pt medium
    var labelMedium: Font { .system(.subheadline, weight: .medium) }// was 14pt medium
    var labelSmall: Font { .system(.footnote, weight: .medium) }   // was 12pt medium

    // Small text
    var caption: Font { .system(.subheadline, weight: .regular) }  // was 14pt regular
    var caption2: Font { .system(.caption2, weight: .regular) }    // was 11pt regular
    var captionBold: Font { .system(.subheadline, weight: .semibold) }// was 14pt semibold
    var captionSmall: Font { .system(.footnote, weight: .regular) }// was 12pt regular
    var footnote: Font { .system(.footnote, weight: .regular) }    // was 12pt regular

    // Display variants
    var displaySmall: Font { .system(.title2, weight: .bold) }     // was 24pt bold

    // Title variant
    var title: Font { .system(.title3, weight: .semibold) }        // was 20pt semibold

    // Interactive
    var button: Font { .system(.body, weight: .semibold) }         // was 16pt semibold
    var buttonLarge: Font { .system(.headline, weight: .semibold) }// was 18pt semibold
    var buttonMedium: Font { .system(.body, weight: .medium) }     // was 16pt medium
    var buttonSmall: Font { .system(.subheadline, weight: .semibold) }// was 14pt semibold
    var link: Font { .system(.body, weight: .medium) }             // was 16pt medium
}

// MARK: - Spacing System

struct SpacingSystem {
    // 4pt grid system
    let xxs: CGFloat = 2   // extra extra small
    let xs: CGFloat = 4    // extra small
    let sm: CGFloat = 8    // small
    let md: CGFloat = 16   // medium
    let lg: CGFloat = 24   // large
    let xl: CGFloat = 32   // extra large
    let xxl: CGFloat = 48  // extra extra large
    
    // Specific use cases
    let buttonPadding: CGFloat = 12
    let cardPadding: CGFloat = 16
    let screenPadding: CGFloat = 20
    let icon: CGFloat = 20  // Added for icon spacing
    let Icon: CGFloat = 20  // Capitalized version
}

// MARK: - Sizing System (Icon is instance property)

struct SizingSystem {
    // Icon as instance property with nested struct
    let Icon = IconSizes()
    
    // Icon sizes struct
    struct IconSizes {
        let xs: CGFloat = 16
        let sm: CGFloat = 20
        let md: CGFloat = 24
        let lg: CGFloat = 32
        let xl: CGFloat = 40
    }
    
    // Direct properties (for backward compatibility)
    let iconXS: CGFloat = 16
    let iconSM: CGFloat = 20
    let iconMD: CGFloat = 24
    let iconLG: CGFloat = 32
    let iconXL: CGFloat = 40
    
    // Card size
    let card: CGFloat = 12
}

// MARK: - Corner Radius System

struct CornerRadiusSystem {
    let xs: CGFloat = 2  // Added
    let small: CGFloat = 4
    let medium: CGFloat = 8
    let large: CGFloat = 12
    let xl: CGFloat = 16
    let full: CGFloat = 9999  // For circular shapes
    
    // Aliases
    var md: CGFloat { medium }
    var sm: CGFloat { small }
    var lg: CGFloat { large }
    
    // Specific use cases
    let button: CGFloat = 8
    let card: CGFloat = 12
    let modal: CGFloat = 16
}

// MARK: - CGFloat Extensions

extension CGFloat {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - View Extensions

extension View {
    // Card Styling
    func cardStyle(designSystem: DesignSystem) -> some View {
        self
            .background(designSystem.colors.backgroundPrimary)
            .cornerRadius(DesignSystem.sizing.card)
            .shadow(color: designSystem.colors.shadow, radius: 4, x: 0, y: 2)
    }

    // Button Styling
    func primaryButtonStyle(designSystem: DesignSystem) -> some View {
        self
            .foregroundColor(.white)
            .font(designSystem.typography.headline)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(designSystem.colors.primaryBlack)
            .cornerRadius(designSystem.cornerRadius.button)
    }

    func secondaryButtonStyle(designSystem: DesignSystem) -> some View {
        self
            .foregroundColor(designSystem.colors.primaryBlack)
            .font(designSystem.typography.headline)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(designSystem.colors.backgroundSecondary)
            .cornerRadius(designSystem.cornerRadius.button)
    }
    
    // Design Shadow modifier with ShadowLevel enum
    func designShadow(_ level: ShadowSystem.ShadowLevel = .medium) -> some View {
        let shadow = ShadowSystem().shadowFor(level)
        return self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
    
    // Design Shadow modifier with ShadowStyle directly
    func designShadow(_ style: ShadowSystem.ShadowStyle) -> some View {
        return self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}

// MARK: - Layout System

struct LayoutSystem {
    // Grid columns based on size class
    func gridColumns(for sizeClass: UserInterfaceSizeClass?) -> Int {
        sizeClass == .regular ? 2 : 1
    }
    
    // Default grid columns (no arguments)
    var gridColumns: Int {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? 2 : 1
        #else
        return 2
        #endif
    }
    
    // Device detection
    var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    // Spacing
    let cardSpacing: CGFloat = 16
    let edgePadding: CGFloat = 20
    let sectionSpacing: CGFloat = 24
    
    // Content widths
    let contentWidth: CGFloat = 600  // Max width for content on larger screens
    let maxCardWidth: CGFloat = 400  // Max width for cards
    let maxFormWidth: CGFloat = 500  // Max width for forms
}

// MARK: - Shadow System

struct ShadowSystem {
    enum ShadowLevel {
        case small
        case medium
        case large
    }
    
    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
    
    func shadowFor(_ level: ShadowLevel) -> ShadowStyle {
        switch level {
        case .small:
            return ShadowStyle(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        case .medium:
            return ShadowStyle(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        case .large:
            return ShadowStyle(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
    }
    
    // Convenience properties
    let small = ShadowStyle(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    let medium = ShadowStyle(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    let large = ShadowStyle(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    
    // Aliases for different naming conventions
    var sm: ShadowStyle { small }
    var md: ShadowStyle { medium }
    var lg: ShadowStyle { large }
}

// MARK: - Animation System

struct AnimationSystem {
    // Animation instances
    let fast = Animation.easeInOut(duration: 0.15)
    let quick = Animation.easeInOut(duration: 0.2)
    let standard = Animation.easeInOut(duration: 0.3)
    let slow = Animation.easeInOut(duration: 0.5)
    let spring = Animation.spring(response: 0.3, dampingFraction: 0.7)
    
    // Duration values (TimeInterval/Double) for use in functions that need raw durations
    let fastDuration: TimeInterval = 0.15
    let quickDuration: TimeInterval = 0.2
    let standardDuration: TimeInterval = 0.3
    let slowDuration: TimeInterval = 0.5
}

