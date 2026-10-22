import AppKit
import SwiftUI

/// How the Graphic style is drawn: three eras of macOS.
enum Theme: String, CaseIterable, Identifiable {
    /// Glossy gel and bevels, like Mac OS X, over a thin layer of glass.
    case aqua
    /// Big Sur to Sequoia: vibrancy and a flat accent.
    case standard = "default"
    /// macOS 26's Liquid Glass.
    case glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aqua: "Aqua"
        case .standard: "Default"
        case .glass: "Liquid Glass"
        }
    }

    var panelRadius: CGFloat {
        switch self {
        case .aqua: 18
        case .standard: 14
        case .glass: 26
        }
    }

    var rowRadius: CGFloat {
        switch self {
        case .aqua: 11
        case .standard: 8
        case .glass: 12
        }
    }
}

/// The Graphic style's colour, picked in Settings and kept as hex.
enum Accent {
    static let defaultHex = "#DB5C94"

    static func color(_ hex: String) -> Color {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return color(defaultHex) }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func hex(_ color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return defaultHex }
        let byte = { (c: CGFloat) in Int((c * 255).rounded()).clamped(to: 0...255) }
        return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }

    /// Text on this colour: black on a light one, white on a dark one.
    static func ink(on color: Color) -> Color {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.62 ? .black : .white
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

extension Color {
    /// This colour mixed toward another, through AppKit so it works before macOS 15.
    func blended(_ other: Color, _ fraction: CGFloat) -> Color {
        Color(nsColor: NSColor(self).blended(withFraction: fraction, of: NSColor(other)) ?? NSColor(self))
    }
}

/// A sakura's head: five notched petals round a small centre.
struct SakuraShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()

        // One petal pointing up, in units of the radius; the others are it turned by 72°
        var petal = Path()
        petal.move(to: CGPoint(x: 0, y: -0.12))
        petal.addCurve(to: CGPoint(x: -0.14, y: -0.98), control1: CGPoint(x: -0.4, y: -0.35), control2: CGPoint(x: -0.44, y: -0.9))
        petal.addLine(to: CGPoint(x: 0, y: -0.84))
        petal.addLine(to: CGPoint(x: 0.14, y: -0.98))
        petal.addCurve(to: CGPoint(x: 0, y: -0.12), control1: CGPoint(x: 0.44, y: -0.9), control2: CGPoint(x: 0.4, y: -0.35))
        petal.closeSubpath()

        for k in 0..<5 {
            let turn = CGAffineTransform(scaleX: r, y: r)
                .concatenating(CGAffineTransform(rotationAngle: CGFloat(k) * .pi * 2 / 5))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
            path.addPath(petal.applying(turn))
        }
        path.addEllipse(in: CGRect(x: center.x - r * 0.13, y: center.y - r * 0.13, width: r * 0.26, height: r * 0.26))
        return path
    }

    /// The menu bar's icon: the shape as a template image, so it follows the bar's colour.
    @MainActor
    static let menuBarImage: NSImage = {
        let renderer = ImageRenderer(content: SakuraShape().fill(.black).frame(width: 16, height: 16))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }()
}

/// The flower beside the field, in the accent with a little depth.
struct SakuraMark: View {
    let accent: Color
    var size: CGFloat = 24

    var body: some View {
        SakuraShape()
            .fill(LinearGradient(colors: [accent.blended(.white, 0.35), accent], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .shadow(color: accent.opacity(0.35), radius: 3, y: 1)
    }
}

/// The panel behind everything, for a style and theme.
struct PanelSurface: View {
    let style: InputStyle
    let theme: Theme
    let accent: Color
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch (style, theme) {
        case (.terminal, _):
            shape.fill(Color.black.opacity(0.92))
                .overlay(shape.strokeBorder(accent.opacity(0.6)))

        case (.graphic, .standard):
            shape.fill(.regularMaterial)
                .overlay(shape.strokeBorder(.white.opacity(0.12)))

        case (.graphic, .glass):
            if #available(macOS 26, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.strokeBorder(.white.opacity(0.25)))
            }

        case (.graphic, .aqua):
            ZStack {
                // The pinch of glass: the desktop shows through
                shape.fill(.ultraThinMaterial)
                // A tint of the accent that darkens toward the bottom, for depth
                shape.fill(LinearGradient(
                    colors: [accent.opacity(0.16), .clear, .black.opacity(0.22)],
                    startPoint: .top, endPoint: .bottom
                ))
                // The gloss over the field, Aqua's shiny top
                shape.fill(LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.30), location: 0),
                        .init(color: .white.opacity(0.10), location: 0.10),
                        .init(color: .clear, location: 0.16),
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
                // A soft inner shadow round the edge
                shape.stroke(.black.opacity(0.35), lineWidth: 8)
                    .blur(radius: 6)
                    .clipShape(shape)
                // The bevel: lit from above
                shape.strokeBorder(LinearGradient(
                    colors: [.white.opacity(0.75), .white.opacity(0.12), .black.opacity(0.35)],
                    startPoint: .top, endPoint: .bottom
                ), lineWidth: 1.5)
            }
        }
    }
}

/// An Aqua gel: a colour with a glossy highlight on top and a glow underneath.
/// Pressed, it goes darker and sinks: the highlight dims and the shadow tightens.
struct AquaGel: View {
    let color: Color
    let radius: CGFloat
    var isPressed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let base = isPressed ? color.blended(.black, 0.25) : color
        ZStack {
            shape.fill(LinearGradient(
                colors: [base.blended(.white, 0.25), base, base.blended(.black, 0.25)],
                startPoint: .top, endPoint: .bottom
            ))
            // Light coming up through the gel from below
            shape.fill(EllipticalGradient(
                colors: [.white.opacity(isPressed ? 0.2 : 0.45), .clear],
                center: .bottom, startRadiusFraction: 0, endRadiusFraction: 0.6
            ))
            // The highlight, over the top half
            GeometryReader { size in
                RoundedRectangle(cornerRadius: max(radius - 2, 2), style: .continuous)
                    .fill(LinearGradient(
                        colors: [.white.opacity(isPressed ? 0.4 : 0.85), .white.opacity(isPressed ? 0.05 : 0.15)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(height: size.size.height * 0.5)
                    .padding(.horizontal, 3)
                    .padding(.top, 1.5)
            }
            shape.strokeBorder(base.blended(.black, 0.4).opacity(0.8), lineWidth: 1)
        }
        .shadow(color: color.opacity(isPressed ? 0.3 : 0.55), radius: isPressed ? 2 : 6, y: isPressed ? 1 : 3)
    }
}

/// Behind the selected row. Pressed, Aqua's gel sinks; the others blink off instead (see ResultRow).
struct SelectionSurface: View {
    let style: InputStyle
    let theme: Theme
    let accent: Color
    var isPressed = false

    var body: some View {
        switch (style, theme) {
        case (.terminal, _):
            RoundedRectangle(cornerRadius: 4).fill(accent)
        case (.graphic, .standard):
            RoundedRectangle(cornerRadius: theme.rowRadius, style: .continuous).fill(accent)
        case (.graphic, .glass):
            let shape = RoundedRectangle(cornerRadius: theme.rowRadius, style: .continuous)
            if #available(macOS 26, *) {
                Color.clear.glassEffect(.regular.tint(accent.opacity(0.75)).interactive(), in: shape)
            } else {
                shape.fill(accent.opacity(0.85))
            }
        case (.graphic, .aqua):
            AquaGel(color: accent, radius: theme.rowRadius, isPressed: isPressed)
        }
    }
}

/// Behind a row under the mouse: a lighter cousin of the selection.
struct HoverSurface: View {
    let style: InputStyle
    let theme: Theme
    let accent: Color

    var body: some View {
        switch (style, theme) {
        case (.terminal, _):
            RoundedRectangle(cornerRadius: 4)
                .fill(accent.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(accent.opacity(0.45)))
        case (.graphic, .standard):
            RoundedRectangle(cornerRadius: theme.rowRadius, style: .continuous).fill(accent.opacity(0.18))
        case (.graphic, .glass):
            let shape = RoundedRectangle(cornerRadius: theme.rowRadius, style: .continuous)
            if #available(macOS 26, *) {
                Color.clear.glassEffect(.regular.interactive(), in: shape)
            } else {
                shape.fill(.white.opacity(0.1))
            }
        case (.graphic, .aqua):
            // A clear bubble: Aqua's gloss and bevel with no colour in it
            let shape = RoundedRectangle(cornerRadius: theme.rowRadius, style: .continuous)
            ZStack {
                shape.fill(accent.opacity(0.12))
                GeometryReader { size in
                    RoundedRectangle(cornerRadius: theme.rowRadius - 2, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .frame(height: size.size.height * 0.5)
                        .padding(.horizontal, 3)
                        .padding(.top, 1.5)
                }
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

/// The square behind a command's icon.
struct IconTile: View {
    let style: InputStyle
    let theme: Theme
    let accent: Color
    let isSelected: Bool
    var isPressed = false

    var body: some View {
        if style == .graphic, theme == .aqua {
            // Every icon is a little gel; the selected row's sits on the big one, so it goes lighter
            AquaGel(color: isSelected ? accent.blended(.white, 0.3) : accent, radius: 8, isPressed: isPressed)
        } else {
            let ink = style == .terminal ? Color.black : Accent.ink(on: accent)
            RoundedRectangle(cornerRadius: style == .terminal ? 4 : 8, style: .continuous)
                .fill(isSelected ? ink.opacity(0.2) : accent.opacity(0.15))
        }
    }

    /// The icon's own colour on this tile.
    static func ink(style: InputStyle, theme: Theme, accent: Color, isSelected: Bool) -> Color {
        if style == .graphic, theme == .aqua { return Accent.ink(on: accent) }
        if isSelected { return style == .terminal ? .black : Accent.ink(on: accent) }
        return accent
    }
}
