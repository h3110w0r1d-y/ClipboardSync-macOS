import Foundation
import SwiftData

// 剪贴板数据模型
struct ClipboardData: Codable {
    let deviceID: String
    let content: String
    let timestamp: Int64
    var type: String = "text"
}

// 同步记录数据模型
struct SyncRecord: Identifiable {
    let id = UUID()
    let content: String
    let timestamp: Date
    let direction: SyncDirection
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
    
    enum SyncDirection {
        case incoming
        case outgoing
    }
}

// 配置数据模型 - 使用 SwiftData 持久化
@Model
final class AppSettings {
    var mqttHost: String
    var mqttPort: UInt16
    var mqttTopic: String
    var mqttUsername: String
    var mqttPassword: String
    var mqttEnableSSL: Bool
    var keepAlive: UInt16
    var autoConnectOnStartup: Bool
    
    init(
        mqttHost: String = "",
        mqttPort: UInt16 = 8883,
        mqttEnableSSL: Bool = true,
        mqttTopic: String = "clipboard",
        mqttUsername: String = "",
        mqttPassword: String = "",
        keepAlive: UInt16 = 60,
        autoConnectOnStartup: Bool = false
    ) {
        self.mqttHost = mqttHost
        self.mqttPort = mqttPort
        self.mqttEnableSSL = mqttEnableSSL
        self.mqttTopic = mqttTopic
        self.mqttUsername = mqttUsername
        self.mqttPassword = mqttPassword
        self.keepAlive = keepAlive
        self.autoConnectOnStartup = autoConnectOnStartup
    }
}
