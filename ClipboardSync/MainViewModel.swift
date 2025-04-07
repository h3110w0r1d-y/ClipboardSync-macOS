import Combine
import SwiftData
import SwiftUI

class MainViewModel: ObservableObject {
    private let modelContainer: ModelContainer
    private let clipboardSync: ClipboardSync

    @Published var connectionStatus: ConnectionStatus = .Disconnect
    @Published var deviceName = Host.current().localizedName ?? "Unknown-Mac"
    @Published var deviceID = ""
    @Published var syncHistory: [SyncRecord] = []

    @Published var mqttHost = ""
    @Published var mqttPort: UInt16 = 8883
    @Published var mqttEnableSSL = true
    @Published var mqttTopic = "clipboard"
    @Published var mqttUsername = ""
    @Published var mqttPassword = ""
    @Published var secretKey = ""
    @Published var keepAlive: UInt16 = 60
    @Published var autoConnectOnStartup = false

    // 初始化时注入上下文
    init(modelContainer: ModelContainer, clipboardSync: ClipboardSync) {
        self.modelContainer = modelContainer
        self.clipboardSync = clipboardSync
        loadSettings()
        print("init mainViewModel")
    }

    func loadSettings() {
        DispatchQueue.main.async {
            var settings: AppSettings
            var descriptor = FetchDescriptor<AppSettings>()
            descriptor.fetchLimit = 1
            let context = self.modelContainer.mainContext
            do {
                settings = (try context.fetch(descriptor).first) ?? AppSettings()
            } catch {
                print("加载设置失败: \(error)")
                settings = AppSettings() // 默认但不保存
            }
            self.mqttHost = settings.mqttHost
            self.mqttPort = settings.mqttPort
            self.mqttEnableSSL = settings.mqttEnableSSL
            self.mqttTopic = settings.mqttTopic
            self.mqttUsername = settings.mqttUsername
            self.mqttPassword = settings.mqttPassword
            self.secretKey = settings.secretKey
            self.keepAlive = settings.keepAlive
            self.autoConnectOnStartup = settings.autoConnectOnStartup
            if (self.autoConnectOnStartup) {
                self.toggleConnection()
            }
        }
    }

    @MainActor
    func saveSettings() {
//        Task { @MainActor in
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<AppSettings>()

        do {
            let existingSettings = try context.fetch(descriptor)

            if let firstSetting = existingSettings.first {
                firstSetting.mqttHost = mqttHost
                firstSetting.mqttPort = mqttPort
                firstSetting.mqttEnableSSL = mqttEnableSSL
                firstSetting.mqttTopic = mqttTopic
                firstSetting.mqttUsername = mqttUsername
                firstSetting.mqttPassword = mqttPassword
                firstSetting.secretKey = secretKey
                firstSetting.keepAlive = keepAlive
                firstSetting.autoConnectOnStartup = autoConnectOnStartup
            } else {
                context.insert(AppSettings(
                    mqttHost: mqttHost,
                    mqttPort: mqttPort,
                    mqttEnableSSL: mqttEnableSSL,
                    mqttTopic: mqttTopic,
                    mqttUsername: mqttUsername,
                    mqttPassword: mqttPassword,
                    secretKey: secretKey,
                    keepAlive: keepAlive,
                    autoConnectOnStartup: autoConnectOnStartup
                ))
            }

            try context.save()
            print("Settings saved successfully")
        } catch {
            print("Error saving settings: \(error)")
        }
//        }
    }

    struct MQTTSettings {
        let host: String
        let port: UInt16
        let enableSSL: Bool
        let topic: String
        let username: String
        let password: String
        let secretKey: String
        let keepAlive: UInt16
    }

    // 操作回调
    var connectAction: (() -> Void)?
    var disconnectAction: (() -> Void)?
    var updateSettingsAction: ((MQTTSettings) -> Void)?
    
    func connect() {
        print("ViewModel: Triggering connect action")
        connectAction?()
    }

    func disconnect() {
        print("ViewModel: Triggering disconnect action")
        disconnectAction?()
    }

    @MainActor
    func toggleConnection() {
        print("ViewModel: Toggle connection")
        if connectionStatus == .Connected {
            disconnect()
        } else {
            saveSettings()
            applySettings()
            connect()
        }
    }
    
    @MainActor
    func applySettings() {
        saveSettings()
        let settings = MQTTSettings(
            host: mqttHost,
            port: mqttPort,
            enableSSL: mqttEnableSSL,
            topic: mqttTopic,
            username: mqttUsername,
            password: mqttPassword,
            secretKey: secretKey,
            keepAlive: keepAlive
        )

        updateSettingsAction?(settings)
    }

    func clearHistory() {
        syncHistory.removeAll()
    }
}
