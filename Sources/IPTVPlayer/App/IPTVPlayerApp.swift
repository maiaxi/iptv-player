import AppKit
import SwiftUI

@main
struct IPTVPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = LibraryStore()
    @State private var player = PlayerModel.shared

    var body: some Scene {
        Window("IPTV Player", id: "library") {
            LibraryView()
                .environment(library)
                .environment(player)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Adicionar fonte…") { library.isAddingSource = true }
                    .keyboardShortcut("n")
                Button("Atualizar biblioteca") { library.refresh() }
                    .keyboardShortcut("r")
                    .disabled(library.selectedSource == nil)
            }
        }

        Window("Player", id: "player") {
            PlayerView()
                .environment(library)
                .environment(player)
                .frame(minWidth: 480, minHeight: 270)
        }
        .windowStyle(.hiddenTitleBar)
        // Secondary Window scenes default to an "associated" (auxiliary) role, which can't
        // properly enter/leave full screen. The player is a first-class window.
        .windowManagerRole(.principal)
        .defaultSize(width: 1280, height: 720)
        .commands {
            CommandMenu("Reprodução") {
                Button(player.isPaused ? "Reproduzir" : "Pausa") { player.togglePause() }
                    .disabled(player.current == nil)
                Divider()
                Button("Canal seguinte") { player.next() }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .disabled(player.queue.count < 2)
                Button("Canal anterior") { player.previous() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(player.queue.count < 2)
                Divider()
                Button(player.isMuted ? "Ativar som" : "Silenciar") { player.toggleMute() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { PlayerModel.shared.shutdown() }
    }
}
