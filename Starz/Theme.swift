//
//  Theme.swift
//  Starz
//

import SwiftUI

extension Color {
    /// Purple accent, #7C4DFF.
    static let accentPurple = Color(red: 0x7C / 255, green: 0x4D / 255, blue: 0xFF / 255)
    /// Lighter purple used for times and secondary accents.
    static let accentPurpleLight = Color(red: 0xA9 / 255, green: 0x8B / 255, blue: 0xFF / 255)
    /// Mint for days where every task is done, #6EE7B7.
    static let mint = Color(red: 0x6E / 255, green: 0xE7 / 255, blue: 0xB7 / 255)
    /// Dark gray for task cards.
    static let card = Color(white: 0.11)
}

/// Black background with a soft purple glow at the top.
struct GlowBackground: View {
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [Color.accentPurple.opacity(0.35), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Liquid Glass on iOS 26. The fallback only exists so the project still
    /// compiles with older Xcode versions that don't have the glass APIs.
    @ViewBuilder
    func floatingGlass(in shape: some Shape = Capsule()) -> some View {
        #if compiler(>=6.2)
        glassEffect(.regular.interactive(), in: shape)
        #else
        background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(.white.opacity(0.15), lineWidth: 1))
        #endif
    }
}

/// Round 44pt glass button with an SF Symbol, used for top navigation buttons.
struct GlassIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .floatingGlass(in: Circle())
        .accessibilityLabel(label)
    }
}

extension View {
    /// Filled purple capsule button: Liquid Glass prominent style on iOS 26.
    @ViewBuilder
    func prominentGlassButton() -> some View {
        #if compiler(>=6.2)
        buttonStyle(.glassProminent).tint(.accentPurple)
        #else
        buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(.accentPurple)
        #endif
    }

    /// iOS 26 sheets are Liquid Glass by default; older SDKs get a material.
    @ViewBuilder
    func glassSheetBackground() -> some View {
        #if compiler(>=6.2)
        self
        #else
        presentationBackground(.ultraThinMaterial)
        #endif
    }
}
