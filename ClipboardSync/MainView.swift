import SwiftUI
import Combine
import SwiftData

struct MainView: View {
    @EnvironmentObject var viewModel: MainViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题和连接状态
            HStack() {
                Image(systemName: viewModel.isConnected ?
                    "arrow.triangle.2.circlepath.circle.fill" :
                    "arrow.triangle.2.circlepath.circle")
                    .font(.system(size: 24))
                    .foregroundColor(viewModel.isConnected ? .green : .red)
                
                Text("剪贴板同步")
                    .font(.title)
                    .bold()
                
                Spacer()
                
                StatusBadge(isConnected: viewModel.isConnected)
            }
            .padding(.vertical)
            
            Divider()
                .padding(.bottom)
            
            // 设备信息
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(title: "设备标识", value: viewModel.deviceName)
                InfoRow(title: "客户端ID", value: viewModel.deviceID)
            }
            .padding(.bottom)
            
            // 基本设置
            VStack(alignment: .leading, spacing: 8.0) {
                Text("MQTT 连接设置")
                    .font(.headline)
                
                HStack {
                    Text("MQTT服务器:")
                    TextField("broker.emqx.io", text: $viewModel.mqttHost)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                HStack {
                    Text("MQTT端口:")
                    TextField("1883", value: $viewModel.mqttPort, formatter: NumberFormatter())
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 70)
                    Toggle("启用SSL", isOn: $viewModel.mqttEnableSSL)
                }
                
                HStack {
                    Text("主题:")
                    TextField("clipboard", text: $viewModel.mqttTopic)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                HStack {
                    Text("用户名:")
                    TextField("可选", text: $viewModel.mqttUsername)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                HStack {
                    Text("密码:")
                    SecureField("可选", text: $viewModel.mqttPassword)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                HStack {
                    Text("保活间隔:")
                    TextField("60", value: $viewModel.keepAlive, formatter: NumberFormatter())
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 70)
                    Text("秒")
                }
                
                Toggle("启动时自动连接", isOn: $viewModel.autoConnectOnStartup)
            }
            .padding(.bottom)
            
            // 最近同步记录
            VStack(alignment: .leading) {
                Text("同步记录")
                    .font(.headline)
                
                if viewModel.syncHistory.isEmpty {
                    Text("尚无同步记录")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .italic()
                        .padding()
                } else {
                    ScrollViewReader { scrollProxy in
                        List {
                            ForEach(viewModel.syncHistory) { record in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(record.direction == .incoming ? "已接收" : "已发送")
                                            .font(.headline)
                                            .foregroundColor(record.direction == .incoming ? .blue : .green)
                                        Text(record.content.prefix(30))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(record.formattedTime)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .id(record.id) // 确保每个项目有唯一ID
                            }
                        }
                        .frame(height: 150)
                        .listStyle(PlainListStyle())
                        .cornerRadius(8)
                        .onChange(of: viewModel.syncHistory.count) { _, _ in
                            // 当记录数量变化时，如果有记录则滚动到第一条（最新的）
                            if let firstRecord = viewModel.syncHistory.first {
                                withAnimation {
                                    scrollProxy.scrollTo(firstRecord.id, anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            // 底部操作按钮
            HStack {
                Button(action: {
                    viewModel.clearHistory()
                }) {
                    Label("清除记录", systemImage: "trash")
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.applySettings()
                }) {
                    Label("应用设置", systemImage: "checkmark.circle")
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.toggleConnection()
                }) {
                    if viewModel.isConnected {
                        Label("断开连接", systemImage: "minus.circle")
                            .foregroundColor(.red)
                    } else {
                        Label("连接", systemImage: "plus.circle")
                            .foregroundColor(.green)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding([.leading, .bottom, .trailing])
        .frame(width: 450, alignment: .top)
        .fixedSize()
    }
}

// 状态标签组件
struct StatusBadge: View {
    let isConnected: Bool
    
    var body: some View {
        Text(isConnected ? "已连接" : "未连接")
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isConnected ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
            .foregroundColor(isConnected ? .green : .red)
            .cornerRadius(20)
    }
}

// 信息行组件
struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title + ":")
                .fontWeight(.medium)
            
            Spacer()
            
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

// 预览
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        MainView(viewModel: {
//            let viewModel = MainViewModel()
//            viewModel.syncHistory = [
////                SyncRecord(content: "Hello, this is a test clipboard content", timestamp: Date(), direction: .outgoing),
////                SyncRecord(content: "Another clipboard content from another device", timestamp: Date().addingTimeInterval(-60), direction: .incoming)
//            ]
//            
//            return viewModel
//        }())
//    }
//}
