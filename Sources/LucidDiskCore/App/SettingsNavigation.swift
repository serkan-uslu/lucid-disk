import Combine

/// Shared selection lets entry points open the relevant Settings tab directly.
@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()

    @Published var selectedTab = "general"
}
