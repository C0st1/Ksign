//
//  SplashView.swift
//  Ksign
//
//  Reworked animated launch screen with full theme sync.
//  Reads the user's accent color & appearance preferences directly
//  from UserDefaults — no dependency on AccentColorManager startup timing.
//

import SwiftUI

struct SplashView: View {

    @ObservedObject var vm: SplashViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // ── Background ──────────────────────────────────────────
            backgroundLayer

            // ── Content ─────────────────────────────────────────────
            VStack(spacing: 0) {
                Spacer()

                // Logo + glow
                logoSection

                // Brand text
                brandingSection
                    .padding(.top, 28)

                Spacer()

                // Bottom accent bar
                bottomBar
            }
        }
        .opacity(vm.splashOpacity)
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        // Always-black base matches the storyboard launch screen,
        // eliminating any white flash during the storyboard → SwiftUI transition.
        Color.black
            .ignoresSafeArea()

        // Subtle radial glow behind the logo
        RadialGradient(
            colors: [
                vm.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.07),
                .clear,
            ],
            center: .center,
            startRadius: 60,
            endRadius: 320
        )
        .ignoresSafeArea()
        .opacity(vm.glowOpacity)
    }

    // MARK: - Logo

    @ViewBuilder
    private var logoSection: some View {
        ZStack {
            // Accent glow ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            vm.accentColor.opacity(0.35),
                            vm.accentColor.opacity(0.08),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .blur(radius: 24)
                .opacity(vm.glowOpacity)

            // The logo image
            Image("ksign_extension.png")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(vm.accentColor)
                .frame(width: 140, height: 140)
                .scaleEffect(vm.logoScale)
                .opacity(vm.logoOpacity)
                .overlay(shimmerOverlay)
        }
    }

    @ViewBuilder
    private var shimmerOverlay: some View {
        // A single light pass across the logo
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .white.opacity(0.25), location: 0.45),
                        .init(color: .white.opacity(0.35), location: 0.5),
                        .init(color: .white.opacity(0.25), location: 0.55),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 140, height: 140)
            .mask(
                Image("ksign_extension.png")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.white)
            )
            .offset(x: vm.shimmerOffset)
            .allowsHitTesting(false)
    }

    // MARK: - Branding

    @ViewBuilder
    private var brandingSection: some View {
        VStack(spacing: 6) {
            Text("Ksign")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [vm.accentColor, vm.accentColor.opacity(0.75)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .opacity(vm.titleOpacity)
                .offset(y: vm.titleOffset)

            Text(String.localized("Sign. Install. Enjoy."))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .opacity(vm.subtitleOpacity)
                .offset(y: vm.subtitleOffset)
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 0) {
            // Thin accent line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, vm.accentColor.opacity(0.5), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 60)
                .opacity(vm.subtitleOpacity)

            Text("v\(Bundle.main.version)")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .opacity(vm.subtitleOpacity)
        }
    }
}
