//
//  SplashViewModel.swift
//  Ksign
//
//  Reworked launch screen with full theme sync.
//

import SwiftUI

// MARK: - Splash Phase
enum SplashPhase {
    case initial       // Logo animating in
    case branding      // App name & tagline fading in
    case ready         // Hold briefly, then dismiss
    case dismissed     // Splash is gone
}

// MARK: - Splash ViewModel
class SplashViewModel: ObservableObject {

    @Published private(set) var phase: SplashPhase = .initial
    @Published var logoScale: CGFloat = 0.6
    @Published var logoOpacity: Double = 0
    @Published var glowOpacity: Double = 0
    @Published var titleOpacity: Double = 0
    @Published var titleOffset: CGFloat = 12
    @Published var subtitleOpacity: Double = 0
    @Published var subtitleOffset: CGFloat = 8
    @Published var shimmerOffset: CGFloat = -200
    @Published var splashOpacity: Double = 1.0

    /// The accent color the user selected (read from UserDefaults so it's
    /// available before AccentColorManager finishes initializing).
    let accentColor: Color
    let accentUIColor: UIColor

    init() {
        // Read the persisted accent color index directly — this avoids any
        // timing dependency on AccentColorManager.shared.
        let index = UserDefaults.standard.integer(forKey: "Feather.accentColor")
        let colors = SplashViewModel._accentPalette()
        let safe = index < colors.count ? index : 0
        self.accentColor = colors[safe].color
        self.accentUIColor = colors[safe].uiColor
    }

    /// Prevents the animation sequence from running more than once.
    private var hasStarted = false

    // MARK: - Animation Sequence

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // Phase 1 — Logo springs in (0 → 0.4s)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
            glowOpacity = 0.55
        }

        // Phase 2 — Branding fades in (0.5 → 0.9s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.phase = .branding
            withAnimation(.easeOut(duration: 0.45)) {
                self?.titleOpacity = 1.0
                self?.titleOffset = 0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
                self?.subtitleOpacity = 1.0
                self?.subtitleOffset = 0
            }
        }

        // Shimmer pass across the logo (0.7 → 1.3s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            withAnimation(.easeInOut(duration: 0.6)) {
                self?.shimmerOffset = 200
            }
        }

        // Phase 3 — Ready to dismiss (1.6s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.phase = .ready
            withAnimation(.easeIn(duration: 0.45)) {
                self?.splashOpacity = 0
            }
        }

        // Phase 4 — Fully dismissed (2.05s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.05) { [weak self] in
            self?.phase = .dismissed
        }
    }

    // MARK: - Accent Palette (mirrors AccentColorManager)

    private static func _accentPalette() -> [(color: Color, uiColor: UIColor)] {
        return [
            (Color(red: 0x53/255, green: 0x94/255, blue: 0xF7/255), UIColor(red: 0x53/255, green: 0x94/255, blue: 0xF7/255, alpha: 1.0)),  // Default
            (Color(red: 0xFF/255, green: 0x8B/255, blue: 0x92/255), UIColor(red: 0xFF/255, green: 0x8B/255, blue: 0x92/255, alpha: 1.0)),  // Cherry
            (.red, .systemRed),
            (.orange, .systemOrange),
            (.yellow, .systemYellow),
            (.green, .systemGreen),
            (.blue, .systemBlue),
            (.purple, .systemPurple),
            (.pink, .systemPink),
            (.indigo, .systemIndigo),
            (.mint, .systemMint),
            (.cyan, .systemCyan),
            (.teal, .systemTeal),
        ]
    }
}
