import Foundation
import SwiftData
import SwiftUI

@main
struct ClipboardSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appDelegate.mainViewModel)
                .modelContainer(appDelegate.modelContainer)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于剪贴板同步") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "剪贴板同步",
                            NSApplication.AboutPanelOptionKey.applicationVersion: "1.0.0",
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: "一个基于MQTT的macOS剪贴板同步工具\nGithub: @h3110w0r1d-y"
                            ),
                        ]
                    )
                    // 在显示关于面板后，查找面板窗口并将其层级设置为浮动（置顶）
                    DispatchQueue.main.async {
                        for window in NSApplication.shared.windows {
                            if window.title.contains("剪贴板同步") || window.title == "关于" || window.title.isEmpty {
                                // 这些条件可能会匹配到关于面板
                                window.level = .floating
                            }
                        }
                    }
                }
            }

            CommandGroup(replacing: .newItem) {}
        }
    }
}
