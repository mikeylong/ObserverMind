import AppKit
import Testing
@testable import ObserverMind

@Test func appKitAppearanceNamesMapToResolvedTheme() {
    #expect(resolvedSystemTheme(for: .darkAqua) == .dark)
    #expect(resolvedSystemTheme(for: .aqua) == .light)
}

@Test func appKitUnknownAppearanceFallsBackToPreferences() {
    let theme = resolvedSystemTheme(
        appleInterfaceStyle: "Dark",
        appKitAppearanceName: .accessibilityHighContrastAqua
    )

    #expect(theme == .dark)
}

@Test func preferencesOverrideAppKitSnapshotForResolvedSystemTheme() {
    let theme = resolvedSystemTheme(
        appleInterfaceStyle: "Dark",
        appKitAppearanceName: .aqua
    )

    #expect(theme == .dark)
}

@Test func resolverDefaultsAutoToLightWhenAppearanceSourcesDoNotResolve() {
    let resolver = DashboardThemeResolver(
        appearanceProvider: DashboardAppearanceProvider { nil }
    )

    #expect(resolver.resolve(.auto) == .light)
}
