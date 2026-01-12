//
//  DesignSystem.swift
//  OralableForProfessionals
//
//  Shared design system matching OralableApp styling.
//
//  Components:
//  - Colors: Same palette as consumer app
//  - Typography: Consistent font styles
//  - Spacing: Standard spacing values
//  - CornerRadius: Rounded corner sizes
//
//  Note: This is a duplicate of OralableApp's DesignSystem
//  to ensure both apps have identical styling.
//

import SwiftUI
import Combine

// MARK: - Main Design System

class DesignSystem: ObservableObject {
    @Published var colors: ColorSystem
    @Published var typography: TypographySystem
    @Published var spacing: SpacingSystem
    @Published var cornerRadius: CornerRadiusSystem

    var Colors: ColorSystem { colors }
    var Typography: TypographySystem { typography }
    var Spacing: SpacingSystem { spacing }
    var CornerRadius: CornerRadiusSystem { cornerRadius }
    var Sizing: SpacingSystem { spacing }

    init() {
        self.colors = ColorSystem()
        self.typography = TypographySystem()
        self.spacing = SpacingSystem()
        self.cornerRadius = CornerRadiusSystem()
    }
}

extension DesignSystem {
    static var Sizing: SizingSystem { SizingSystem() }
    static var Layout: LayoutSystem { LayoutSystem() }
    static var Shadow: ShadowSystem { ShadowSystem() }
    static var Animation: AnimationSystem { AnimationSystem() }
    static var sizing: SizingSystem { SizingSystem() }
}

struct ColorSystem {
    let textPrimary = Color.primary
    let textSecondary = Color.secondary
    let textTertiary = Color(UIColor.tertiaryLabel)
    let textDisabled = Color(UIColor.quaternaryLabel)

    let backgroundPrimary = Color(UIColor.systemBackground)
    let backgroundSecondary = Color(UIColor.secondarySystemBackground)
    let backgroundTertiary = Color(UIColor.tertiarySystemBackground)
    let backgroundGrouped = Color(UIColor.systemGroupedBackground)

    let primaryBlack = Color.black
    let primaryWhite = Color.white

    let gray50 = Color(UIColor.systemGray6)
    let gray100 = Color(UIColor.systemGray5)
    let gray200 = Color(UIColor.systemGray4)
    let gray300 = Color(UIColor.systemGray3)
    let gray400 = Color(UIColor.systemGray2)
    let gray500 = Color(UIColor.systemGray)

    let border = Color(UIColor.separator)
    let divider = Color(UIColor.separator)

    let info = Color.blue
    let warning = Color.orange
    let error = Color.red
    let success = Color.green

    let muscleActivity = Color.purple
    let movement = Color.blue
    let heartRate = Color.red
    let battery = Color.green
    let temperature = Color.orange
    let oralWellness = Color.purple  // Primary wellness metric color

    let shadow = Color.black.opacity(0.1)
}

struct TypographySystem {
    // Using iOS system fonts (SF Pro) for better integration and no missing font errors

    // Headings
    var h1: Font { .system(size: 34, weight: .bold) }
    var h2: Font { .system(size: 28, weight: .semibold) }
    var h3: Font { .system(size: 22, weight: .semibold) }
    var h4: Font { .system(size: 18, weight: .medium) }

    // Large title and headline
    var largeTitle: Font { .system(size: 34, weight: .bold) }
    var headline: Font { .system(size: 17, weight: .semibold) }

    // Body variants
    var body: Font { .system(size: 16, weight: .regular) }
    var bodyBold: Font { .system(size: 16, weight: .bold) }
    var bodyMedium: Font { .system(size: 16, weight: .medium) }
    var bodyLarge: Font { .system(size: 18, weight: .regular) }
    var bodySmall: Font { .system(size: 14, weight: .regular) }

    // Label variants
    var labelLarge: Font { .system(size: 16, weight: .medium) }
    var labelMedium: Font { .system(size: 14, weight: .medium) }
    var labelSmall: Font { .system(size: 12, weight: .medium) }

    // Small text
    var caption: Font { .system(size: 14, weight: .regular) }
    var caption2: Font { .system(size: 11, weight: .regular) }
    var captionBold: Font { .system(size: 14, weight: .semibold) }
    var footnote: Font { .system(size: 12, weight: .regular) }

    // Display variants
    var displaySmall: Font { .system(size: 24, weight: .bold) }

    // Title variant
    var title: Font { .system(size: 20, weight: .semibold) }

    // Interactive
    var button: Font { .system(size: 16, weight: .semibold) }
    var buttonLarge: Font { .system(size: 18, weight: .semibold) }
    var buttonSmall: Font { .system(size: 14, weight: .semibold) }
    var link: Font { .system(size: 16, weight: .medium) }
}

struct SpacingSystem {
    let xxs: CGFloat = 2
    let xs: CGFloat = 4
    let sm: CGFloat = 8
    let md: CGFloat = 16
    let lg: CGFloat = 24
    let xl: CGFloat = 32
    let xxl: CGFloat = 48

    let buttonPadding: CGFloat = 12
    let cardPadding: CGFloat = 16
    let screenPadding: CGFloat = 20
    let icon: CGFloat = 20
}

struct SizingSystem {
    let Icon = IconSizes()

    struct IconSizes {
        let xs: CGFloat = 16
        let sm: CGFloat = 20
        let md: CGFloat = 24
        let lg: CGFloat = 32
        let xl: CGFloat = 40
    }

    let iconXS: CGFloat = 16
    let iconSM: CGFloat = 20
    let iconMD: CGFloat = 24
    let iconLG: CGFloat = 32
    let iconXL: CGFloat = 40
    let card: CGFloat = 12
}

struct CornerRadiusSystem {
    let xs: CGFloat = 2
    let small: CGFloat = 4
    let medium: CGFloat = 8
    let large: CGFloat = 12
    let xl: CGFloat = 16
    let full: CGFloat = 9999

    var md: CGFloat { medium }
    var sm: CGFloat { small }
    var lg: CGFloat { large }

    let button: CGFloat = 8
    let card: CGFloat = 12
    let modal: CGFloat = 16
}

struct LayoutSystem {
    func gridColumns(for sizeClass: UserInterfaceSizeClass?) -> Int {
        sizeClass == .regular ? 2 : 1
    }

    var gridColumns: Int {
        UIDevice.current.userInterfaceIdiom == .pad ? 2 : 1
    }

    var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    let cardSpacing: CGFloat = 16
    let edgePadding: CGFloat = 20
    let sectionSpacing: CGFloat = 24
    let contentWidth: CGFloat = 600
    let maxCardWidth: CGFloat = 400
    let maxFormWidth: CGFloat = 500
}

struct ShadowSystem {
    enum ShadowLevel { case small, medium, large }

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    func shadowFor(_ level: ShadowLevel) -> ShadowStyle {
        switch level {
        case .small: return ShadowStyle(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        case .medium: return ShadowStyle(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        case .large: return ShadowStyle(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
    }

    let small = ShadowStyle(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    let medium = ShadowStyle(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    let large = ShadowStyle(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
}

struct AnimationSystem {
    let fast = Animation.easeInOut(duration: 0.15)
    let quick = Animation.easeInOut(duration: 0.2)
    let standard = Animation.easeInOut(duration: 0.3)
    let slow = Animation.easeInOut(duration: 0.5)
    let spring = Animation.spring(response: 0.3, dampingFraction: 0.7)
}

extension View {
    func cardStyle(designSystem: DesignSystem) -> some View {
        self
            .background(designSystem.colors.backgroundPrimary)
            .cornerRadius(DesignSystem.sizing.card)
            .shadow(color: designSystem.colors.shadow, radius: 4, x: 0, y: 2)
    }

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

    func designShadow(_ level: ShadowSystem.ShadowLevel = .medium) -> some View {
        let shadow = ShadowSystem().shadowFor(level)
        return self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
