import Cocoa
import CocoaMQTT
import Foundation
import IOKit
import CryptoKit
import CommonCrypto


class ClipboardSync: NSObject {
    // MQTT客户端实例
    private var mqttClient: CocoaMQTT5!
    // 设备ID，用于唯一标识设备
    private var deviceID: String!
    // 设备名称
    private var deviceName: String!
    // 剪贴板的更改计数，用于检测剪贴板内容的变化
    private var changeCount: Int = NSPasteboard.general.changeCount
    // 定时器，用于定期检查剪贴板内容
    private var syncTimer: Timer!
    // 连接状态，指示是否已连接到MQTT服务器
    private var connectionStatus: ConnectionStatus = .Disconnect

    // MQTT 配置
    // MQTT 主题，用于消息的发布和订阅
    private var mqttTopic = "clipboard"
    private var secretKey = Data(count: 32)
    private var secretIV = Data(count: 16)
    private var needReconnect = false

    // 回调
    // 连接状态改变时的回调
    var onConnectionStatusChanged: ((ConnectionStatus) -> Void)?
    // 同步事件发生时的回调
    var onSyncEvent: ((SyncRecord) -> Void)?

    // 在 ClipboardSync.swift 中添加或修改
    override init() {
        super.init()
        deviceName = Host.current().localizedName ?? "Unknown-Mac"
        deviceID = getHardwareUUID()
        mqttClient = CocoaMQTT5(clientID: deviceID)
        mqttClient.delegate = self
    }

    func getHardwareUUID() -> String {
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))

        if platformExpert == 0 {
            return "Unknown"
        }

        guard let uuid = (IORegistryEntryCreateCFProperty(platformExpert, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0).takeRetainedValue() as? String) else {
            IOObjectRelease(platformExpert)
            return "Unknown"
        }

        IOObjectRelease(platformExpert)
        return uuid
    }

    /// 将ViewModel与ClipboardSync连接起来
    func connectViewModel(_ viewModel: MainViewModel) {
        print("Connecting ViewModel to ClipboardSync")
        // 将当前状态同步到 ViewModel
        viewModel.deviceName = deviceName
        viewModel.deviceID = deviceID
        viewModel.connectionStatus = connectionStatus

        // 设置 ViewModel 的回调函数
        viewModel.connectAction = { [weak self] in
            print("Connect action triggered from ViewModel")
            self?.connect()
        }

        viewModel.disconnectAction = { [weak self] in
            print("Disconnect action triggered from ViewModel")
            self?.disconnect()
        }

        viewModel.updateSettingsAction = { [weak self] settings in
            print("Update settings action triggered from ViewModel")
            self?.updateSettings(
                mqttHost: settings.host,
                mqttPort: settings.port,
                mqttEnableSSL: settings.enableSSL,
                mqttTopic: settings.topic,
                mqttUsername: settings.username,
                mqttPassword: settings.password,
                secretKey: settings.secretKey,
                keepAlive: settings.keepAlive
            )
        }

        // 设置回调给 ClipboardSync
        onConnectionStatusChanged = { [weak viewModel] status in
            DispatchQueue.main.async {
                print("Connection status changed: \(status)")
                viewModel?.connectionStatus = status
            }
        }

        onSyncEvent = { [weak viewModel] record in
            DispatchQueue.main.async {
                print("Sync event received: \(record.content.prefix(20))...")
                viewModel?.syncHistory.insert(record, at: 0)
                if (viewModel?.syncHistory.count ?? 0) > 50 {
                    viewModel?.syncHistory.removeLast()
                }
            }
        }
    }

    /// 连接到MQTT服务器
    func connect() {
        // 启动监控剪贴板
        connectionStatus = .Connecting
        onConnectionStatusChanged?(.Connecting)
        _ = mqttClient.connect()
        startMonitoringClipboard()
    }

    /// 断开与MQTT服务器的连接
    func disconnect(reconnect: Bool = false) {
        needReconnect = false
        stopMonitoringClipboard()
        mqttClient.disconnect()
    }

    /// 更新MQTT设置
    func updateSettings(mqttHost: String, mqttPort: UInt16, mqttEnableSSL: Bool, mqttTopic: String,
                        mqttUsername: String, mqttPassword: String, secretKey: String, keepAlive: UInt16) {
        let newSecretKey = Data(SHA256.hash(data: secretKey.data(using: .utf8)!))
        
        // 如果关键连接参数改变且当前已连接，则重新连接
        if (
            mqttClient.host != mqttHost ||
            mqttClient.port != mqttPort ||
            mqttClient.enableSSL != mqttEnableSSL ||
            self.mqttTopic != mqttTopic ||
            mqttClient.username != mqttUsername ||
            mqttClient.password != mqttPassword ||
            self.secretKey != newSecretKey ||
            mqttClient.keepAlive != keepAlive
        ) {
            mqttClient.host = mqttHost
            mqttClient.port = mqttPort
            mqttClient.enableSSL = mqttEnableSSL
            self.mqttTopic = mqttTopic
            mqttClient.username = mqttUsername
            mqttClient.password = mqttPassword
            self.secretKey = newSecretKey
            self.secretIV = newSecretKey.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Data in
                var result = Data(count: 16)
                result.withUnsafeMutableBytes { (resultBuffer: UnsafeMutableRawBufferPointer) in
                    for i in 0..<16 {
                        resultBuffer[i] = buffer[i] ^ buffer[i + 16]
                    }
                }
                return result
            }
            mqttClient.keepAlive = keepAlive
            if connectionStatus == .Connected {
                disconnect(reconnect: true)
            }
        }
        
    }

    /// 开始监控剪贴板内容的变化
    private func startMonitoringClipboard() {
        changeCount = NSPasteboard.general.changeCount
        syncTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(checkClipboard),
            userInfo: nil,
            repeats: true
        )
    }
    
    private func stopMonitoringClipboard() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    /// 检查剪贴板内容是否有变化
    @objc private func checkClipboard() {
        guard connectionStatus == .Connected else { return }
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != changeCount {
            changeCount = pasteboard.changeCount
            // 检查是否有文本内容且文本同步已启用
            if let clipboardString = pasteboard.string(forType: .string) {
                sendClipboardContent(clipboardString)
            }
        }
    }

    /// 发送剪贴板内容到MQTT服务器
    private func sendClipboardContent(_ content: String) {
        do {
            let clipboardData = ClipboardData(deviceID: deviceID, content: content, timestamp: Int64(Date().timeIntervalSince1970 * 1000))
            let jsonData = try JSONEncoder().encode(clipboardData)
            let properties = MqttPublishProperties()

            let aes256 = try AES256(key: secretKey, iv: secretIV)
            let result = try aes256.encrypt(jsonData)
            let message = CocoaMQTT5Message(topic: mqttTopic, payload: Array(result))

            mqttClient.publish(message, properties: properties)
            // 记录发送事件
            let record = SyncRecord(content: content, timestamp: Date(), direction: .outgoing)
            onSyncEvent?(record)
        } catch {
            print("Error encoding clipboard data: \(error)")
        }
    }
}


// MARK: - CocoaMQTTDelegate
extension ClipboardSync: CocoaMQTT5Delegate {
    /// 处理MQTT连接确认消息
    func mqtt5(_ mqtt5: CocoaMQTT5, didConnectAck ack: CocoaMQTTCONNACKReasonCode, connAckData: MqttDecodeConnAck?) {
        if ack == .success {
            connectionStatus = .Connected
            needReconnect = true
            let subscription = MqttSubscription(topic: mqttTopic, qos: .qos1)
            subscription.noLocal = true
            mqttClient.subscribe([subscription])
            onConnectionStatusChanged?(.Connected)

            // 更新菜单栏图标
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.updateStatusBarIcon(isConnected: true)
            }
        }
    }

    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishAck id: UInt16, pubAckData: MqttDecodePubAck?) {}

    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishRec id: UInt16, pubRecData: MqttDecodePubRec?) {}

    func mqtt5(_ mqtt5: CocoaMQTT5, didPublishMessage message: CocoaMQTT5Message, id: UInt16) {}

    /// 处理MQTT消息接收事件
    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveMessage message: CocoaMQTT5Message, id: UInt16, publishData: MqttDecodePublish?) {
        print("收到MQTT消息: \(message.topic)")

        do {
            let cipher = try AES256(key: secretKey, iv: secretIV)
            let decryptedData = try cipher.decrypt(Data(message.payload))
            
            let clipboardData = try JSONDecoder().decode(ClipboardData.self, from: decryptedData)

            // 忽略自己发送的消息
            if clipboardData.deviceID == deviceID {
                return
            }
            // 更新剪贴板内容
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(clipboardData.content, forType: .string)

            // 更新我们的changeCount以避免重新发送
            changeCount = pasteboard.changeCount

            // 记录接收事件
            let record = SyncRecord(content: clipboardData.content, timestamp: Date(), direction: .incoming)
            onSyncEvent?(record)

        } catch {
            print("Error decoding clipboard data: \(error)")
        }
    }

    /// 处理MQTT主题订阅成功事件
    func mqtt5(_ mqtt5: CocoaMQTT5, didSubscribeTopics success: NSDictionary, failed: [String], subAckData: MqttDecodeSubAck?) {}

    /// 处理MQTT主题取消订阅事件
    func mqtt5(_ mqtt5: CocoaMQTT5, didUnsubscribeTopics topics: [String], unsubAckData: MqttDecodeUnsubAck?) {}

    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveDisconnectReasonCode reasonCode: CocoaMQTTDISCONNECTReasonCode) {}

    func mqtt5(_ mqtt5: CocoaMQTT5, didReceiveAuthReasonCode reasonCode: CocoaMQTTAUTHReasonCode) {}

    /// 处理MQTT PING发送事件
    func mqtt5DidPing(_ mqtt5: CocoaMQTT5) {}

    /// 处理MQTT PONG响应事件
    func mqtt5DidReceivePong(_ mqtt5: CocoaMQTT5) {}

    /// 处理MQTT断开连接事件
    func mqtt5DidDisconnect(_ mqtt5: CocoaMQTT5, withError err: Error?) {
        if connectionStatus == .Connecting {
            connectionStatus = .ConnectionFailure
            onConnectionStatusChanged?(.ConnectionFailure)
        } else {
            connectionStatus = .Disconnect
            onConnectionStatusChanged?(.Disconnect)
        }
        // 更新菜单栏图标
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.updateStatusBarIcon(isConnected: false)
        }
        
        if needReconnect {
            Thread.sleep(forTimeInterval: 1)
            connect()
        }
    }
}

enum ConnectionStatus {
    case Connected
    case Disconnect
    case ConnectionFailure
    case Connecting
}
