import Combine
import Sparkle
import SwiftUI

/// Sparkle auto-updates. The feed (appcast.xml) is attached to every GitHub release by CI; the app
/// reads it from the latest release, and updates are verified with the EdDSA key in Info.plist.
@MainActor
final class Updater {
    static let shared = Updater()

    /// nil when running outside an .app bundle (`swift run`, debug builds from .build): there's no
    /// Info.plist with a feed, and Sparkle would show an error at launch.
    let controller: SPUStandardUpdaterController?

    private init() {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
}

/// "Check for Updates…" menu item, disabled while a check is already running.
struct CheckForUpdatesButton: View {
    @StateObject private var model = CheckForUpdatesModel(updater: Updater.shared.controller?.updater)

    var body: some View {
        Button("Check for Updates…") { Updater.shared.controller?.checkForUpdates(nil) }
            .disabled(!model.canCheck)
    }
}

@MainActor
private final class CheckForUpdatesModel: ObservableObject {
    @Published var canCheck = false

    init(updater: SPUUpdater?) {
        updater?.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }
}
