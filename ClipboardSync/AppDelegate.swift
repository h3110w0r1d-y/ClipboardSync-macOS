import Cocoa
import SwiftUI
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    let modelContainer: ModelContainer
    let mainViewModel: MainViewModel
    let clipboardSync: ClipboardSync
    
    var mainWindow: NSWindow?
    var statusItem: NSStatusItem?
    
    override init() {
        // 初始化ModelContainer
        do {
            modelContainer = try ModelContainer(
                for: AppSettings.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: false)
            )
        } catch {
            fatalError("无法创建ModelContainer: \(error)")
        }
        
        // 初始化ClipboardSync
        clipboardSync = ClipboardSync()
        
        // 初始化ViewModel并传入依赖
        mainViewModel = MainViewModel(modelContainer: modelContainer, clipboardSync: clipboardSync)
        clipboardSync.connectViewModel(mainViewModel)
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("AppDelegate: applicationDidFinishLaunching")
        NSApp.delegate = self
        setupStatusBar()
        
        NSApp.setActivationPolicy(.regular)
        
        // 设置窗口代理，以便捕获窗口事件
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeMainNotification),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillCloseNotification),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "icloud.slash", accessibilityDescription: "Clipboard Sync")
            button.imagePosition = .imageLeft
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示设置", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc private func windowDidBecomeMainNotification(_ notification: Notification) {
        mainWindow = notification.object as? NSWindow
        setupWindow(mainWindow!)
    }
    
    @objc private func windowWillCloseNotification(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == mainWindow {
            // 当窗口关闭时，切换为辅助应用（不在Dock上显示）
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    private func setupWindow(_ window: NSWindow) {
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    
    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
    }
    
    @objc private func quitApp() {
        clipboardSync.disconnect()
        NSApplication.shared.terminate(self)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // 关闭窗口后应用继续在后台运行
    }
    
    func updateStatusBarIcon(isConnected: Bool) {
        if let button = statusItem?.button {
            let imageName = isConnected ? "bolt.horizontal.icloud.fill" : "icloud.slash"
            button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Clipboard Sync")
        }
    }
}
