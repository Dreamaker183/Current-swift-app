import SwiftUI
import Charts
import PassKit
import Combine
import UserNotifications
import SplineRuntime 
import WebKit  // Replace SplineRuntime with WebKit for WebView approach
import AVFoundation  // Add AVFoundation for speech synthesis

// MARK: - ObservableObject for Global Settings
class AppSettings: ObservableObject {
    @Published var darkMode: Bool = false
}

// Add DeviceControlService after the AppSettings class
class DeviceControlService: ObservableObject {
    static let shared = DeviceControlService()
    @Published var deviceToToggle: (id: Int, turnOn: Bool)? = nil
}

// MARK: - NotificationManager
class NotificationManager {
    static let shared = NotificationManager()
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            } else {
                print("Notification permission granted: \(granted)")
            }
        }
    }
    
    func sendLowBalanceNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Low Balance Alert"
        content.body = "Your remaining balance is below 15%. Please recharge soon."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "LowBalanceNotification", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling low balance notification: \(error.localizedDescription)")
            }
        }
    }
    
    func sendPowerCutNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Power Cut Warning"
        content.body = "Your usage has exceeded your balance. Initiating power cut demo."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "PowerCutNotification", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling power cut notification: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Color Palette
struct AppColors {
    static let primary   = Color(hex: "#6366f1")
    static let secondary = Color(hex: "#22d3ee")
    static let background = Color(hex: "#111111")
    static let surface   = Color(hex: "#111111")
    static let text      = Color(hex: "#f8fafc")
    static let textMuted = Color(hex: "#94a3b8")
    static let success   = Color(hex: "#22c55e")
    static let warning   = Color(hex: "#f59e0b")
    static let error     = Color(hex: "#ef4444")
}

// MARK: - Data Models
struct UsagePoint: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    let usage: Double
    let predicted: Double
    
    static func == (lhs: UsagePoint, rhs: UsagePoint) -> Bool {
        return lhs.id == rhs.id &&
               lhs.time == rhs.time &&
               lhs.usage == rhs.usage &&
               lhs.predicted == rhs.predicted
    }
}

struct Device: Identifiable {
    let id: Int
    let name: String
    var usage: Double
    var isOn: Bool
}

struct PowerPlan: Identifiable {
    let id = UUID()
    let name: String
    let price: Double
    let usageLimit: String
    let features: [String]
    let icon: String
    
    static let plans = [
        PowerPlan(
            name: "Daily Plan",
            price: 50,
            usageLimit: "10 kWh/day",
            features: ["Real-time monitoring", "Daily usage alerts", "Basic analytics"],
            icon: "sun.max"
        ),
        PowerPlan(
            name: "Weekly Plan",
            price: 250,
            usageLimit: "70 kWh/week",
            features: ["All Daily Plan features", "Weekly reports", "Usage predictions", "Power-saving tips"],
            icon: "calendar.badge.clock"
        ),
        PowerPlan(
            name: "Monthly Plan",
            price: 900,
            usageLimit: "300 kWh/month",
            features: ["All Weekly Plan features", "Advanced analytics", "Priority support", "Custom alerts", "Energy optimization"],
            icon: "chart.bar.fill"
        )
    ]
}

// MARK: - ThingSpeak Data Fetch
struct TSRoot: Decodable {
    let feeds: [TSFeed]?
}

struct TSFeed: Decodable {
    let created_at: String?
    let field1: String?
    let field2: String?
    let field3: String?
    let field4: String?
    let field5: String?
    let field6: String?
    let field7: String?
    let field8: String?
}

fileprivate extension TSFeed {
    func value(forKey field: String) -> Any? {
        switch field {
        case "field1": return field1
        case "field2": return field2
        case "field3": return field3
        case "field4": return field4
        case "field5": return field5
        case "field6": return field6
        case "field7": return field7
        case "field8": return field8
        default: return nil
        }
    }
}

// MARK: - UsageViewModel (Optimized with Combine)
class UsageViewModel: ObservableObject {
    @Published var usageData: [UsagePoint] = []
    @Published var totalUsedThisMonth: Double = 0.0
    @Published var remainingBalance: Double = 100.0
    @Published var batteryTemperature: Double = 25.0
    
    private let channelID = "2834155"
    private let readKey = "KXJYZHUQCKBVSJUO"
    private let usageField = "field1"
    private let predictedField = "field3"
    private let balanceField = "field2"
    private let temperatureField = "field6"
    
    private var cancellable: AnyCancellable?
    
    init() {
        cancellable = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchData()
            }
    }
    
    /// Public method to cancel the timer
    func stop() {
        cancellable?.cancel()
    }
    
    deinit {
        cancellable?.cancel()
    }
    
    private func fetchData() {
        guard let url = URL(string: "https://api.thingspeak.com/channels/\(channelID)/feeds.json?api_key=\(readKey)&results=1") else { return }
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            do {
                let tsRoot = try JSONDecoder().decode(TSRoot.self, from: data)
                if let feeds = tsRoot.feeds, let lastFeed = feeds.last {
                    DispatchQueue.main.async {
                        if let usageStr = lastFeed.value(forKey: self.usageField) as? String,
                           let usageVal = Double(usageStr),
                           let predStr = lastFeed.value(forKey: self.predictedField) as? String,
                           let predVal = Double(predStr) {
                            if usageVal < 1.0 && predVal < 1.0 {
                                let newPoint = UsagePoint(time: Date(), usage: usageVal, predicted: predVal)
                                if self.usageData.count > 50 { self.usageData.removeFirst() }
                                self.usageData.append(newPoint)
                                self.totalUsedThisMonth += usageVal
                            }
                        }
                        if let balanceStr = lastFeed.value(forKey: self.balanceField) as? String,
                           let balanceVal = Double(balanceStr) {
                            self.remainingBalance = min(max(balanceVal, 0), 100)
                        }
                        if let tempStr = lastFeed.value(forKey: self.temperatureField) as? String,
                           let tempVal = Double(tempStr) {
                            self.batteryTemperature = tempVal
                        }
                    }
                }
            } catch {
                print("ThingSpeak parse error: \(error)")
            }
        }.resume()
    }
}

// MARK: - Spline Integration
struct SplineSceneView: View {
    var body: some View {
        let url = URL(string: "https://build.spline.design/FwVnrkVb6FnHJZEdzATL/scene.splineswift")!
        SplineView(sceneFileURL: url)
            .ignoresSafeArea()
    }
}

// MARK: - Main ContentView
// MARK: - Main ContentView
struct ContentView: View {
    @StateObject private var appSettings = AppSettings()
    @StateObject private var usageVM = UsageViewModel()
    @ObservedObject private var deviceControlService = DeviceControlService.shared
    
    @State private var showSidebar = false
    @State private var navigationSelection: String? = "dashboard"
    
    @State private var selectedDevice: Device?
    @State private var devices: [Device] = [
        Device(id: 1, name: "Light", usage: 2.4, isOn: false),
        Device(id: 2, name: "Washing Machine", usage: 1.2, isOn: false),
        Device(id: 3, name: "Smart TV", usage: 0.8, isOn: false)
    ]
    
    @State private var showPowerPlans = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var planLimit: Double? = 300.0
    @State private var lowBalanceNotificationSent = false
    
    // Add state for showing the loading view
    @State private var showLoadingView = true
    
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                ScrollView {
                    VStack(spacing: 16) {
                        switch navigationSelection {
                        case "dashboard": dashboardView
                        case "preferences": preferencesView
                        case "help": helpSupportView
                        case "batteryMonitor": BatteryMonitorView()
                        case "aiAssistant": AIAssistantView()
                        default: dashboardView
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 800)
                }
                .frame(maxWidth: .infinity)
            }
            
            if showSidebar { sidebarView }
            
            // Overlay the LoadingView when showLoadingView is true
            if showLoadingView {
                LoadingView()
                    .ignoresSafeArea()
                    .zIndex(1) // Ensure it appears above other content
                    .transition(.opacity) // Smooth fade transition
            }
        }
        .foregroundColor(AppColors.text)
        .preferredColorScheme(appSettings.darkMode ? .dark : .light)
        .environmentObject(appSettings)
        .sheet(isPresented: $showPowerPlans) { PowerPlansView() }
        .onDisappear { usageVM.stop() }
        .onAppear {
            NotificationManager.shared.requestAuthorization()
            // Dismiss the loading view after 8 seconds (matching the LoadingView animation duration)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    showLoadingView = false
                }
            }
        }
        .onReceive(usageVM.$remainingBalance) { newBalance in
            if newBalance < 15 && !lowBalanceNotificationSent {
                NotificationManager.shared.sendLowBalanceNotification()
                lowBalanceNotificationSent = true
            } else if newBalance >= 15 && lowBalanceNotificationSent {
                lowBalanceNotificationSent = false
            }
        }
        .onReceive(deviceControlService.$deviceToToggle) { deviceInfo in
            if let deviceInfo = deviceInfo {
                // Find the device by ID
                if let index = devices.firstIndex(where: { $0.id == deviceInfo.id }) {
                    // Toggle the device
                    devices[index].isOn = deviceInfo.turnOn
                    
                    // Update usage for the device
                    if devices[index].isOn {
                        devices[index].usage = Double.random(in: 0.5...3.0)
                    } else {
                        devices[index].usage = 0.0
                    }
                    
                    // Set as selected device
                    selectedDevice = devices[index]
                    
                    // Send command to ThingSpeak
                    sendDeviceLEDCommand(for: devices[index])
                    
                    // Reset the toggle request
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        deviceControlService.deviceToToggle = nil
                    }
                }
            }
        }
    }
}

// MARK: - ContentView Subviews
extension ContentView {
    private var headerView: some View {
        ZStack {
            Rectangle()
                .fill(AppColors.background.opacity(0.95))
                .overlay(Rectangle().stroke(AppColors.surface, lineWidth: 1).opacity(0.8))
                .frame(height: 60)
                .shadow(color: AppColors.background.opacity(0.5), radius: 5, x: 0, y: 2)
            HStack {
                Button {
                    withAnimation { showSidebar = true }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .regular))
                        .padding(8)
                }
                .background(AppColors.surface.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Spacer()
                
                Button(action: {
                    navigationSelection = "dashboard"
                }) {
                    Text("Current+")
                        .font(Font.custom("nano", size: 33))
                        .gradientForeground(from: Color.white, to: Color.gray)
                }

                Spacer()
                
                Button {
                    navigationSelection = "preferences"
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .regular))
                        .padding(8)
                }
                .background(AppColors.surface.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .foregroundColor(AppColors.text)
            .padding(.horizontal, 16)
        }
        .frame(height: 60)
    }
    
    private var dashboardView: some View {
        VStack(spacing: 16) { usageSection; devicesSection }
    }
    
    private var preferencesView: some View { PreferencesViewUI() }
    private var helpSupportView: some View { HelpSupportViewUI() }
    
    private var usageSection: some View {
        let isMobile = (horizontalSizeClass == .compact)
        return Group {
            if isMobile {
                VStack(spacing: 16) {
                    planUsageGauge
                    usageChart
                }
            } else {
                HStack(spacing: 16) {
                    planUsageGauge
                    usageChart
                }
            }
        }
    }
    
    // MARK: Optimized Gauge View with Reduced Particles & .drawingGroup()
    private var planUsageGauge: some View {
        let remaining = usageVM.remainingBalance
        let ratio = remaining / 100.0
        
        // Extract nested state variables
        let rotationDegrees = 0.0
        let pulseEffect = true
        let showParticles = false
        let particleOpacity = 0.0
        
        return ZStack {
            // Base layer
            gaugeBaseLayer(rotationDegrees: rotationDegrees)
            
            // Energy particles - extracted to reduce complexity
            gaugeParticles(ratio: ratio, remaining: remaining, showParticles: showParticles, particleOpacity: particleOpacity)
            
            // Progress indicator
            gaugeProgressLayer(ratio: ratio, remaining: remaining)
            
            // Inner glow effect
            gaugeInnerGlow(remaining: remaining, pulseEffect: pulseEffect)
                
            // Center content
            gaugeCenterContent(remaining: remaining, pulseEffect: pulseEffect)
            
            // Critical indicator
            if remaining <= 15 {
                CriticalBalanceIndicator()
                    .frame(width: 210, height: 210)
            }
        }
        .drawingGroup()
        .frame(minWidth: 0, maxWidth: .infinity)
    }
    
    // Helper methods to break down the complex gauge view
    
    private func gaugeBaseLayer(rotationDegrees: Double) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            AppColors.background.opacity(0.6),
                            AppColors.background.opacity(0.0)
                        ]),
                        center: .center,
                        startRadius: 50,
                        endRadius: 120
                    )
                )
                .frame(width: 220, height: 220)
                .blur(radius: 15)
            
            Circle()
                .fill(AppColors.surface)
                .frame(width: 180, height: 180)
                .shadow(color: AppColors.background, radius: 10, x: 10, y: 10)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    AppColors.surface.opacity(0.9),
                                    AppColors.background.opacity(0.3)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    AppColors.surface.opacity(0.1),
                                    AppColors.background.opacity(0.4)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
            
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color.gray.opacity(0.3),
                            Color.white.opacity(0.1),
                            Color.gray.opacity(0.3),
                            Color.black.opacity(0.2),
                            Color.gray.opacity(0.3),
                        ]),
                        center: .center
                    ),
                    lineWidth: 10
                )
                .frame(width: 160, height: 160)
                .blur(radius: 0.4)
                
            gaugeTickMarks()
            
            // Rotating decorative circles
            Circle()
                .trim(from: 0.0, to: 0.8)
                .stroke(
                    AppColors.surface.opacity(0.4),
                    lineWidth: 1
                )
                .frame(width: 190, height: 190)
                .rotationEffect(.degrees(rotationDegrees))
                .onAppear {
                    withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                        // Use a local variable to hold the animation target
                        let _ = 360
                    }
                }
                
            Circle()
                .trim(from: 0.0, to: 0.6)
                .stroke(
                    AppColors.surface.opacity(0.4),
                    lineWidth: 1
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-rotationDegrees * 0.7))
        }
    }
    
    private func gaugeTickMarks() -> some View {
        ForEach(0..<60) { index in
            Group {
                if index % 5 == 0 {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.white.opacity(0.8), AppColors.textMuted]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2, height: 10)
                        .offset(y: -80)
                        .shadow(color: Color.black.opacity(0.3), radius: 1, x: 1, y: 1)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 1, height: 4)
                        .offset(y: -80)
                }
            }
            .rotationEffect(.degrees(Double(index) * 6))
        }
    }
    
    private func gaugeParticles(ratio: Double, remaining: Double, showParticles: Bool, particleOpacity: Double) -> some View {
        ForEach(0..<10) { index in
            let delay = Double(index) * 0.05
            let angle = Double.random(in: -90..<270) * (ratio)
            let distance = Double.random(in: 60..<90)
            
            Circle()
                .fill(getGaugeColor(remaining: remaining).opacity(0.8))
                .frame(width: Double.random(in: 2..<4), height: Double.random(in: 2..<4))
                .blur(radius: 0.5)
                .offset(
                    x: cos(angle * .pi / 180) * distance,
                    y: sin(angle * .pi / 180) * distance
                )
                .opacity(showParticles ? particleOpacity * Double.random(in: 0.3..<1.0) : 0)
                .animation(
                    .easeOut(duration: Double.random(in: 0.8..<1.5))
                    .delay(delay),
                    value: particleOpacity
                )
        }
    }
    
    private func gaugeProgressLayer(ratio: Double, remaining: Double) -> some View {
        Circle()
            .trim(from: 0.0, to: CGFloat(ratio))
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        getGaugeColor(remaining: remaining).opacity(0.8),
                        getGaugeColor(remaining: remaining),
                        getGaugeColor(remaining: remaining).opacity(0.9)
                    ]),
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(ratio * 360 - 90)
                ),
                style: StrokeStyle(lineWidth: 14, lineCap: .round)
            )
            .frame(width: 160, height: 160)
            .rotationEffect(.degrees(-90))
            .shadow(color: getGaugeColor(remaining: remaining).opacity(0.6), radius: 8, x: 0, y: 0)
            .overlay(gaugeProgressIndicator(ratio: ratio, remaining: remaining))
            .animation(.spring(response: 0.8, dampingFraction: 0.7).speed(0.7), value: ratio)
    }
    
    private func gaugeProgressIndicator(ratio: Double, remaining: Double) -> some View {
        Circle()
            .fill(getGaugeColor(remaining: remaining))
            .frame(width: 12, height: 12)
            .shadow(color: getGaugeColor(remaining: remaining).opacity(0.8), radius: 2, x: 0, y: 0)
            .offset(x: 80 * cos((ratio * 360 - 90) * .pi / 180), y: 80 * sin((ratio * 360 - 90) * .pi / 180))
            .opacity(ratio > 0.03 ? 1 : 0)
    }
    
    private func gaugeInnerGlow(remaining: Double, pulseEffect: Bool) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [
                        getGaugeColor(remaining: remaining).opacity(pulseEffect ? 0.4 : 0.1),
                        getGaugeColor(remaining: remaining).opacity(0.0)
                    ]),
                    center: .center,
                    startRadius: 20,
                    endRadius: 80
                )
            )
            .frame(width: 120, height: 120)
            .blur(radius: 8)
    }
    
    private func gaugeCenterContent(remaining: Double, pulseEffect: Bool) -> some View {
        VStack(spacing: 6) {
            AnimatedCounterText(value: Float(remaining), format: "%.0f%%")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(AppColors.text)
                .shadow(color: AppColors.background.opacity(0.5), radius: 1, x: 1, y: 1)
            
            Text("Remaining Balance")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppColors.textMuted)
            
            HStack(spacing: 8) {
                Image(systemName: remaining < 20 ? "exclamationmark.triangle.fill" : "bolt.fill")
                    .font(.system(size: 12))
                    .foregroundColor(getGaugeColor(remaining: remaining))
                    .symbolEffect(.pulse, options: .repeating, value: remaining < 15)
                
                Text(getStatusText(remaining: remaining))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(getGaugeColor(remaining: remaining))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(getGaugeColor(remaining: remaining).opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(getGaugeColor(remaining: remaining).opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: getGaugeColor(remaining: remaining).opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
        .scaleEffect(pulseEffect && remaining < 15 ? 1.03 : 1.0)
    }

    // Animated counter for the gauge
    struct AnimatedCounterText: View {
        let value: Float
        let format: String
        
        @State private var displayValue: Float = 0
        
        var body: some View {
            Text(String(format: format, displayValue))
                .onAppear {
                    displayValue = value
                }
                .onChange(of: value) { oldValue, newValue in
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.8).speed(1.2)) {
                        displayValue = newValue
                    }
                }
        }
    }

    // Critical balance indicator with subtle animations
    struct CriticalBalanceIndicator: View {
        @State private var rotation = 0.0
        @State private var scale = 1.0
        @State private var opacity = 0.7
        
        var body: some View {
            ZStack {
                Circle()
                    .stroke(AppColors.error.opacity(opacity), lineWidth: 2)
                    .scaleEffect(scale)
                
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 6]))
                    .foregroundColor(AppColors.error.opacity(opacity * 0.8))
                    .rotationEffect(.degrees(rotation))
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    opacity = 0.3
                    scale = 1.05
                }
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
    }

    private func getGaugeColor(remaining: Double) -> Color {
        switch remaining {
        case 70...100:
            return AppColors.success
        case 30..<70:
            return AppColors.warning
        default:
            return AppColors.error
        }
    }

    private func getStatusText(remaining: Double) -> String {
        switch remaining {
        case 80...100:
            return "Optimal"
        case 50..<80:
            return "Good"
        case 25..<50:
            return "Moderate"
        case 15..<25:
            return "Low Balance"
        default:
            return "Critical!"
        }
    }
    
    private var usageChart: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            AppColors.surface,
                            AppColors.surface.opacity(0.8)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: AppColors.background.opacity(0.5), radius: 8, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.surface.opacity(0.6), lineWidth: 1)
                )
            
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Real-time Usage vs Prediction")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppColors.text)
                        
                        Text("Live monitoring of power consumption")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textMuted)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppColors.success)
                            .frame(width: 8, height: 8)
                            .modifier(PulseEffect())
                        
                        Text("Syncing...")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppColors.textMuted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(AppColors.surface.opacity(0.6))
                    )
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 6) {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 8, height: 8)
                            
                            Text("Real-time Usage")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color.purple)
                        }
                        
                        ChartContainer(
                            data: usageVM.usageData,
                            valueKey: \.usage,
                            color: .purple,
                            title: "Current"
                        )
                    }
                    .frame(maxWidth: .infinity)
                    
                    AnimatedDivider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 6) {
                            Circle()
                                .fill(AppColors.success)
                                .frame(width: 8, height: 8)
                            
                            Text("Predicted Usage")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppColors.success)
                        }
                        
                        ChartContainer(
                            data: usageVM.usageData,
                            valueKey: \.predicted,
                            color: AppColors.success,
                            title: "Predicted"
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
                
                HStack(spacing: 0) {
                    ForEach(0..<5) { index in
                        let hour = Calendar.current.component(.hour, from: Date()) - 2 + index
                        Text(timeLabel(hour: hour))
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.textMuted)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity)
                            .id("time-\(index)")
                    }
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
    }

    private func timeLabel(hour: Int) -> String {
        let adjustedHour = (hour + 24) % 24
        if adjustedHour == 0 { return "12AM" }
        else if adjustedHour < 12 { return "\(adjustedHour)AM" }
        else if adjustedHour == 12 { return "12PM" }
        else { return "\(adjustedHour - 12)PM" }
    }

    struct PulseEffect: ViewModifier {
        @State private var pulsing = false
        
        func body(content: Content) -> some View {
            content
                .scaleEffect(pulsing ? 1.2 : 0.8)
                .opacity(pulsing ? 1.0 : 0.6)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
                .onAppear { pulsing = true }
        }
    }

    struct AnimatedDivider: View {
        @State private var animating = false
        
        var body: some View {
            VStack(spacing: 6) {
                ForEach(0..<5) { index in
                    Circle()
                        .fill(AppColors.textMuted.opacity(animating ? 0.8 : 0.3))
                        .frame(width: 4, height: 4)
                        .animation(
                            Animation.easeInOut(duration: 1.5)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .onAppear { animating = true }
        }
    }

    struct ChartContainer: View {
        let data: [UsagePoint]
        let valueKey: KeyPath<UsagePoint, Double>
        let color: Color
        let title: String
        
        @State private var animateChart = false
        @State private var highlightedIndex: Int? = nil
        
        var body: some View {
            VStack {
                ZStack(alignment: .topTrailing) {
                    if let lastValue = data.last?[keyPath: valueKey] {
                        HStack {
                            Text(String(format: "%.2f", lastValue * 100000))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(color)
                            
                            Text("W/min")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.textMuted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(color.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(color.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    Chart {
                        ForEach(Array(data.enumerated()), id: \.element.id) { index, point in
                            LineMark(
                                x: .value("Time", point.time),
                                y: .value("Value", animateChart ? point[keyPath: valueKey] : 0.0)
                            )
                            .foregroundStyle(color.gradient)
                            .interpolationMethod(.catmullRom)
                            .symbol {
                                if highlightedIndex == index {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 8, height: 8)
                                        .shadow(color: color.opacity(0.6), radius: 2, x: 0, y: 0)
                                } else {
                                    EmptyView()
                                }
                            }
                            
                            AreaMark(
                                x: .value("Time", point.time),
                                y: .value("Value", animateChart ? point[keyPath: valueKey] : 0.0)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [color.opacity(0.3), color.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let dateVal = value.as(Date.self) {
                                    Text(shortTimeFormatter.string(from: dateVal))
                                        .font(.system(size: 10))
                                        .foregroundColor(AppColors.textMuted)
                                }
                            }
                            AxisGridLine(stroke: StrokeStyle(dash: [3]))
                                .foregroundStyle(AppColors.surface.opacity(0.6).gradient)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let doubleValue = value.as(Double.self) {
                                    Text(String(format: "%.0f", doubleValue * 100000))
                                        .font(.system(size: 10))
                                        .foregroundColor(AppColors.textMuted)
                                }
                            }
                            AxisGridLine(stroke: StrokeStyle(dash: [3]))
                                .foregroundStyle(AppColors.surface.opacity(0.6).gradient)
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let xPosition = value.location.x
                                            let dataCount = data.count
                                            guard dataCount > 0 else { return }
                                            let index = min(max(Int(xPosition / geometry.size.width * CGFloat(dataCount)), 0), dataCount - 1)
                                            highlightedIndex = index
                                        }
                                        .onEnded { _ in
                                            highlightedIndex = nil
                                        }
                                )
                        }
                    }
                }
                .frame(height: 180)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.0)) {
                        animateChart = true
                    }
                }
                .onChange(of: data) { oldValue, newValue in
                    if oldValue.count != newValue.count {
                        animateChart = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeInOut(duration: 1.0)) {
                                animateChart = true
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var devicesSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(AppColors.surface).shadow(radius: 4)
            VStack(alignment: .leading, spacing: 12) {
                Text("Connected Devices")
                    .font(.system(size: 16, weight: .semibold))
                let isMobile = (horizontalSizeClass == .compact)
                let columns = isMobile ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach($devices) { $device in
                        DeviceTile(device: $device, isSelected: device.id == selectedDevice?.id)
                            .onTapGesture {
                                device.isOn.toggle()
                                if device.isOn {
                                    device.usage = Double.random(in: 0.5...3.0)
                                } else {
                                    device.usage = 0.0
                                }
                                selectedDevice = device
                                sendDeviceLEDCommand(for: device)
                            }
                    }
                }
            }
            .padding()
        }
    }
    
    private var sidebarView: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { withAnimation { showSidebar = false } }
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Settings")
                            .font(.system(size: 20, weight: .bold))
                        Spacer()
                        Button {
                            withAnimation { showSidebar = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .bold))
                                .padding(8)
                                .background(AppColors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .foregroundColor(AppColors.text)
                    sidebarLinks
                    Spacer()
                }
                .padding()
                .frame(width: min(proxy.size.width * 0.7, 300))
                .background(AppColors.surface)
                .transition(.move(edge: .leading))
            }
        }
    }
    
    private var sidebarLinks: some View {
        VStack(alignment: .leading, spacing: 16) {
            sidebarLink(icon: "chart.bar.fill", label: "Dashboard") {
                navigationSelection = "dashboard"
                withAnimation { showSidebar = false }
            }
            sidebarLink(icon: "battery.100.bolt", label: "Battery Monitor") {
                navigationSelection = "batteryMonitor"
                withAnimation { showSidebar = false }
            }
            sidebarLink(icon: "brain.head.profile", label: "AI Assistant") {
                navigationSelection = "aiAssistant"
                withAnimation { showSidebar = false }
            }
            sidebarLink(icon: "creditcard", label: "Power Plans") {
                withAnimation {
                    showSidebar = false
                    showPowerPlans = true
                }
            }
            sidebarLink(icon: "questionmark.circle", label: "Help & Support") {
                navigationSelection = "help"
                withAnimation { showSidebar = false }
            }
        }
    }
    
    private func sidebarLink(icon: String, label: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.system(size: 16))
        .foregroundColor(AppColors.textMuted)
        .padding(.vertical, 4)
        .onTapGesture { action() }
    }
}

// MARK: - DeviceTile
struct DeviceTile: View {
    @Binding var device: Device
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(device.name)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Image(systemName: "power")
                    .foregroundColor(device.isOn ? AppColors.success : AppColors.textMuted)
                    .font(.system(size: 14))
            }
            Text("\(String(format: "%.1f", device.usage)) kWh/hr")
                .font(.system(size: 12))
                .foregroundColor(AppColors.textMuted)
        }
        .padding()
        .background(isSelected ? AppColors.surface.opacity(0.8) : .clear)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? AppColors.primary : AppColors.surface, lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - LED Command Sender
extension ContentView {
    func sendDeviceLEDCommand(for device: Device) {
        let fieldNumber: Int
        switch device.id {
        case 1: fieldNumber = 7
        case 2: fieldNumber = 8
        default: return
        }

        let value = device.isOn ? 1 : 0
        let status = device.isOn ? "ON" : "OFF"
        let apiKey = "YCT2QXNYDWJOMK9B"

        for i in 0..<15 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i*2)) {
                let urlString = "https://api.thingspeak.com/update?api_key=\(apiKey)&field\(fieldNumber)=\(value)"
                guard let url = URL(string: urlString) else { return }

                URLSession.shared.dataTask(with: url) { _, _, error in
                    if let error = error {
                        print("Attempt \(i + 1): Error setting device \(device.name) to \(status) - \(error.localizedDescription)")
                    } else {
                        print("Attempt \(i + 1): Device \(device.name) set to \(status), field\(fieldNumber)=\(value)")
                    }
                }.resume()
            }
        }
    }
}

// MARK: - PreferencesView
struct PreferencesViewUI: View {
    @EnvironmentObject var appSettings: AppSettings
    @State private var notifications = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preferences")
                        .font(.title.bold())
                        .foregroundColor(AppColors.text)
                    Text("Customize Your Experience")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                PreferencesSection(title: "Account") {
                    PreferencesItem(icon: "person.crop.circle", iconColor: .blue, title: "Account Details", subtitle: "Manage your info") {} rightContent: { EmptyView() }
                    Divider().background(AppColors.surface.opacity(0.5))
                    PreferencesItem(icon: "rectangle.portrait.and.arrow.right", iconColor: .red, title: "Logout", subtitle: "Sign out") {} rightContent: { EmptyView() }
                }
                
                PreferencesSection(title: "Appearance") {
                    PreferencesItem(icon: appSettings.darkMode ? "moon.fill" : "sun.max.fill", iconColor: appSettings.darkMode ? .indigo : .yellow, title: "Dark Mode", subtitle: "Switch themes") {
                        appSettings.darkMode.toggle()
                    } rightContent: {
                        Toggle("", isOn: $appSettings.darkMode).labelsHidden()
                    }
                }
                
                PreferencesSection(title: "Notifications") {
                    PreferencesItem(icon: "bell.fill", iconColor: .green, title: "Enable Notifications", subtitle: "Receive updates") {
                        notifications.toggle()
                    } rightContent: {
                        Toggle("", isOn: $notifications).labelsHidden()
                    }
                    Divider().background(AppColors.surface.opacity(0.5))
                    PreferencesItem(icon: "gearshape", iconColor: .gray, title: "Notification Settings", subtitle: "Customize preferences") {} rightContent: { EmptyView() }
                }
                
                PreferencesSection(title: "About") {
                    PreferencesItem(icon: "person.crop.circle", iconColor: .purple, title: "App Version", subtitle: "1.0.0 (Build 42)") {} rightContent: { EmptyView() }
                    Divider().background(AppColors.surface.opacity(0.5))
                    PreferencesItem(icon: "chevron.right", iconColor: .gray, title: "Terms of Service") {} rightContent: { EmptyView() }
                    Divider().background(AppColors.surface.opacity(0.5))
                    PreferencesItem(icon: "chevron.right", iconColor: .gray, title: "Privacy Policy") {} rightContent: { EmptyView() }
                }
            }
            .padding()
        }
        .background(AppColors.background.ignoresSafeArea())
    }
}

struct PreferencesSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.text)
            content
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(12)
    }
}

struct PreferencesItem<RightContent: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let action: (() -> Void)?
    @ViewBuilder let rightContent: RightContent
    
    init(icon: String, iconColor: Color, title: String, subtitle: String? = nil, action: (() -> Void)? = nil, @ViewBuilder rightContent: () -> RightContent) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.rightContent = rightContent()
    }
    
    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppColors.text)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textMuted)
                    }
                }
                Spacer()
                rightContent
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.textMuted)
            }
            .padding(8)
            .background(AppColors.surface.opacity(0.0001))
            .cornerRadius(8)
        }
    }
}

// MARK: - HelpSupportView
struct HelpSupportViewUI: View {
    struct SupportOption: Identifiable {
        let id = UUID()
        let icon: String
        let iconColor: Color
        let title: String
        let description: String
        let action: () -> Void
    }
    
    @State private var supportOptions: [SupportOption] = [
        SupportOption(icon: "book.fill", iconColor: .blue, title: "FAQs", description: "Quick answers to common questions", action: { print("Open FAQs") }),
        SupportOption(icon: "phone.fill", iconColor: .green, title: "Contact Support", description: "Speak with our team", action: { print("Open Phone Support") }),
        SupportOption(icon: "envelope.fill", iconColor: .purple, title: "Email Support", description: "support@ecurrentplus.com", action: { print("Open Email") }),
        SupportOption(icon: "bubble.left.and.bubble.right.fill", iconColor: .cyan, title: "Live Chat", description: "Instant support", action: { print("Open Live Chat") })
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text("Help & Support")
                            .font(.title.bold())
                            .gradientForeground(from: .white, to: .gray)
                        Text("Get the assistance you need")
                            .font(.subheadline)
                            .foregroundColor(AppColors.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                
                VStack(spacing: 12) {
                    ForEach(supportOptions) { option in
                        Button {
                            option.action()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 20))
                                    .foregroundColor(option.iconColor)
                                    .frame(width: 32, height: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(AppColors.text)
                                    Text(option.description)
                                        .font(.system(size: 14))
                                        .foregroundColor(AppColors.textMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(AppColors.textMuted)
                            }
                            .padding(12)
                            .background(AppColors.surface)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Additional Resources")
                        .font(.headline)
                        .foregroundColor(AppColors.text)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Need more help? Check our documentation and tutorials.")
                            .foregroundColor(AppColors.textMuted)
                            .font(.callout)
                        Button("Open Documentation") { print("Documentation clicked") }
                            .font(.callout.bold())
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(AppColors.primary)
                            .cornerRadius(10)
                    }
                    .padding()
                    .background(AppColors.surface)
                    .cornerRadius(12)
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .background(AppColors.background.ignoresSafeArea())
    }
}

// MARK: - PowerPlansView
struct PowerPlansView: View {
    @State private var selectedPlan: PowerPlan?
    @Environment(\.dismiss) private var dismiss
    @State private var animateCards = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("Choose Your Plan")
                            .font(.title.bold())
                            .foregroundColor(AppColors.text)
                        Text("Select the plan that fits your energy needs")
                            .font(.subheadline)
                            .foregroundColor(AppColors.textMuted)
                    }
                    .padding(.top)
                    
                    VStack(spacing: 16) {
                        ForEach(PowerPlan.plans) { plan in
                            PlanCard(plan: plan, isSelected: selectedPlan?.id == plan.id) {
                                withAnimation { selectedPlan = plan }
                            }
                            .offset(x: animateCards ? 0 : -300)
                            .opacity(animateCards ? 1 : 0)
                            .animation(
                                .spring(response: 0.6, dampingFraction: 0.8)
                                .delay(Double(PowerPlan.plans.firstIndex(where: { $0.id == plan.id }) ?? 0) * 0.1),
                                value: animateCards
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    if let selectedPlan = selectedPlan {
                        VStack(spacing: 16) {
                            Button(action: {}) {
                                Text("Subscribe for $\(String(format: "%.2f", selectedPlan.price))/mo")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(LinearGradient(colors: [AppColors.primary, AppColors.secondary], startPoint: .leading, endPoint: .trailing))
                                    .cornerRadius(16)
                                    .shadow(radius: 8)
                            }
                            PaymentButton(plan: selectedPlan)
                                .frame(maxWidth: .infinity)
                                .frame(height: 45)
                        }
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 32)
            }
            .background(AppColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.textMuted)
                            .imageScale(.large)
                    }
                }
            }
        }
        .onAppear { withAnimation { animateCards = true } }
    }
}

struct PlanCard: View {
    let plan: PowerPlan
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: plan.icon)
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 40, height: 40)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Circle())
                    Spacer()
                    Text("$\(String(format: "%.2f", plan.price))")
                        .font(.title2.bold())
                        .foregroundColor(AppColors.text)
                }
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.name)
                            .font(.headline)
                            .foregroundColor(AppColors.text)
                        Text(plan.usageLimit)
                            .font(.subheadline)
                            .foregroundColor(AppColors.textMuted)
                    }
                    Divider().background(AppColors.textMuted.opacity(0.3))
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(plan.features, id: \.self) { feature in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AppColors.success)
                                Text(feature)
                                    .font(.caption)
                                    .foregroundColor(AppColors.textMuted)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(AppColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isSelected ? .blue : .clear, lineWidth: 2)
                    )
            )
            .shadow(radius: isSelected ? 8 : 4)
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3), value: isSelected)
        }
    }
}

struct PaymentButton: UIViewRepresentable {
    let plan: PowerPlan
    
    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .checkout, paymentButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.handleTap), for: .touchUpInside)
        return button
    }
    
    func updateUIView(_ uiView: PKPaymentButton, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(plan: plan) }
    
    class Coordinator: NSObject, PKPaymentAuthorizationViewControllerDelegate {
        let plan: PowerPlan
        init(plan: PowerPlan) { self.plan = plan }
        
        @objc func handleTap() {
            let request = PKPaymentRequest()
            request.merchantIdentifier = "your.merchant.id"
            request.supportedNetworks = [.visa, .masterCard, .amex]
            request.merchantCapabilities = .threeDSecure
            request.countryCode = "HK"
            request.currencyCode = "HKD"
            let summaryItem = PKPaymentSummaryItem(label: plan.name, amount: NSDecimalNumber(value: plan.price))
            request.paymentSummaryItems = [summaryItem]
            guard let paymentVC = PKPaymentAuthorizationViewController(paymentRequest: request) else { return }
            paymentVC.delegate = self
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let window = scene.windows.first,
               let rootVC = window.rootViewController {
                rootVC.present(paymentVC, animated: true)
            }
        }
        
        func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
            completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
        }
        
        func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
            controller.dismiss(animated: true, completion: nil)
        }
    }
}

// MARK: - BatteryMonitorView
struct BatteryMonitorView: View {
    @StateObject private var usageVM = UsageViewModel()
    @State private var hourlyUsage: [HourlyUsagePoint] = generateHourlyUsage()
    @State private var solarData: SolarSystemData = generateSolarData()
    @State private var showBars = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Battery Usage")
                        .font(.title.bold())
                    Text("Last 24 Hours")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 0) { SplineSceneView().frame(height: 390) }
                consumptionCard
                solarSystemStatusCard
                powerSourceDetailsCard
            }
            .padding()
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeIn(duration: 0.8)) { showBars = true }
            Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                let newUsage = generateHourlyUsage()
                let newSolar = generateSolarData()
                withAnimation(.easeInOut(duration: 0.8)) {
                    hourlyUsage = newUsage
                    solarData = newSolar
                    showBars = true
                }
            }
        }
    }
    
    private var consumptionCard: some View {
        let totalDailyUsage = hourlyUsage.reduce(0) { $0 + $1.usage }
        return VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Power Consumption")
                        .font(.headline)
                    Text("\(String(format: "%.1f", totalDailyUsage)) kWh Today")
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted)
                }
                Spacer()
            }
            Chart {
                ForEach(hourlyUsage) { point in
                    BarMark(x: .value("Hour", hourLabel(point.hour)),
                            y: .value("Usage", showBars ? point.usage : 0.0))
                        .foregroundStyle(AppColors.success)
                        .cornerRadius(4)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let usage = value.as(Double.self) {
                            Text("\(Int(usage))")
                                .font(.caption2)
                                .foregroundColor(AppColors.textMuted)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(dash: [3]))
                        .foregroundStyle(AppColors.surface.gradient)
                }
            }
            .frame(height: 200)
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
    }
    
    private var solarSystemStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Arduino Battery System")
                    .font(.headline)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(solarData.systemStatus == .optimal ? .green : .yellow)
                        .frame(width: 8, height: 8)
                    Text(solarData.systemStatus == .optimal ? "Optimal" : "Reduced Power")
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Main Battery")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(solarData.batteryPercentage))%")
                        .font(.caption)
                        .foregroundColor(AppColors.textMuted)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(AppColors.surface.opacity(0.4))
                            .cornerRadius(4)
                            .frame(height: 6)
                        Rectangle()
                            .fill(Color.green)
                            .cornerRadius(4)
                            .frame(width: geo.size.width * (CGFloat(solarData.batteryPercentage)/100), height: 6)
                    }
                }
                .frame(height: 6)
                Text("\(String(format: "%.1f", solarData.currentCharge)) / \(String(format: "%.1f", solarData.totalCapacity)) kWh Available")
                    .font(.caption2)
                    .foregroundColor(AppColors.textMuted)
            }
            .padding(8)
            .background(AppColors.surface.opacity(0.5))
            .cornerRadius(8)
            VStack(spacing: 8) {
                powerFlowRow(icon: "sun.max.fill", label: "Solar Production", value: "\(String(format: "%.1f", solarData.solarProduction)) kW", iconColor: .yellow)
                powerFlowRow(icon: "thermometer", label: "Room Temperature", value: "\(String(format: "%.1f", usageVM.batteryTemperature))°C", iconColor: .blue)
                powerFlowRow(icon: "bolt.fill", label: "Daily Production", value: "\(String(format: "%.1f", solarData.dailyProduction)) kWh", iconColor: .green)
            }
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
        .frame(maxWidth: .infinity)
    }
    
    private var powerSourceDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Power Source History")
                .font(.headline)
            ForEach(hourlyUsage.suffix(6)) { point in
                HStack {
                    Image(systemName: (point.hour >= 6 && point.hour < 18) ? "sun.max.fill" : "moon.fill")
                        .foregroundColor((point.hour >= 6 && point.hour < 18) ? .yellow : .gray)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hourLabel(point.hour))
                            .font(.subheadline)
                        Text("Battery Drain: \(String(format: "%.1f", point.batteryDrain)) kWh")
                            .font(.caption)
                            .foregroundColor(AppColors.textMuted)
                    }
                    Spacer()
                    Text("\(String(format: "%.1f", point.usage)) kWh")
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
                .background(AppColors.surface.opacity(0.4))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
    }
    
    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12AM" }
        else if hour < 12 { return "\(hour)AM" }
        else if hour == 12 { return "12PM" }
        else { return "\(hour - 12)PM" }
    }
    
    private func powerFlowRow(icon: String, label: String, value: String, iconColor: Color) -> some View {
        HStack {
            Label {
                Text(label)
                    .font(.subheadline)
            } icon: {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
            }
            Spacer()
            Text(value)
                .font(.subheadline)
        }
        .padding(6)
        .background(AppColors.surface.opacity(0.4))
        .cornerRadius(8)
    }
}

enum SystemStatus { case optimal, reduced }

struct SolarSystemData {
    let totalCapacity: Double
    let currentCharge: Double
    let solarProduction: Double
    let gridConsumption: Double
    let dailyProduction: Double
    let systemStatus: SystemStatus
    
    var batteryPercentage: Double { totalCapacity }
}

struct HourlyUsagePoint: Identifiable {
    let id = UUID()
    let hour: Int
    let usage: Double
    let batteryDrain: Double
}

func generateSolarData() -> SolarSystemData {
    let totalCapacity: Double = 13.5
    let currentCharge = Double.random(in: 0..<totalCapacity)
    let status: SystemStatus = Bool.random() ? .optimal : .reduced
    return SolarSystemData(
        totalCapacity: totalCapacity,
        currentCharge: currentCharge,
        solarProduction: Double.random(in: 1...6),
        gridConsumption: Double.random(in: 0...3),
        dailyProduction: Double.random(in: 5...30),
        systemStatus: status
    )
}

func generateHourlyUsage() -> [HourlyUsagePoint] {
    (0..<24).map { hour in
        let base = (hour >= 8 && hour <= 20) ? Double.random(in: 3...6) : Double.random(in: 1...3)
        let drain = Double.random(in: 0.5...2.5)
        return HourlyUsagePoint(hour: hour, usage: base, batteryDrain: drain)
    }
}

private let shortTimeFormatter: DateFormatter = {
    let df = DateFormatter()
    df.timeStyle = .short
    df.dateStyle = .none
    return df
}()

extension View {
    func gradientForeground(from: Color, to: Color) -> some View {
        self.overlay(
            LinearGradient(
                gradient: Gradient(colors: [from, to]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .mask(self)
    }
}

// MARK: - AIAssistantView
struct AIAssistantView: View {
    @State private var userInput = ""
    @State private var messages: [ChatMessage] = []
    @State private var isTyping = false
    @State private var showSplineModel = true
    @State private var isListening = false
    @State private var keyboardHeight: CGFloat = 0
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // Speech synthesizer for text-to-speech
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var isSpeaking = false
    
    // Environment object to access UIApplication for keyboard dismissal
    @Environment(\.colorScheme) private var colorScheme // Needed to make FocusState work
    @FocusState private var isInputFieldFocused: Bool
    
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                if showSplineModel {
                    // AI assistant 3D model view using WebView instead of SplineRuntime
                    ZStack {
                        SplineWebView(url: "https://prod.spline.design/tcSb8pCtKfhHcvzK/scene.splinecode")
                            .frame(height: 280)
                            .background(
                                LinearGradient(
                                    colors: [AppColors.background, AppColors.background.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            gradient: Gradient(colors: [
                                                AppColors.primary.opacity(0.3),
                                                AppColors.background.opacity(0.0)
                                            ]),
                                            center: .center,
                                            startRadius: 5,
                                            endRadius: 120
                                        )
                                    )
                                    .frame(width: 220, height: 220)
                                    .blur(radius: 15)
                                    .opacity(isTyping || isSpeaking ? 1 : 0.3)
                                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isTyping || isSpeaking),
                                alignment: .center
                            )
                    }
                    .padding(.top)
                }
                
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if isTyping {
                                HStack(alignment: .bottom, spacing: 8) {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 24))
                                        .foregroundColor(AppColors.primary)
                                    
                                    TypingIndicator()
                                        .frame(width: 50, height: 30)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(AppColors.surface)
                                        .cornerRadius(16)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading)
                                .id("typingIndicator")
                            }
                            
                            // Add padding at the bottom to prevent messages from being hidden by the keyboard
                            Spacer().frame(height: keyboardHeight > 0 ? keyboardHeight + 60 : 80)
                        }
                        .padding()
                    }
                    .onChange(of: messages) { oldValue, newValue in
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isTyping) { oldValue, newValue in
                        if newValue {
                            withAnimation {
                                proxy.scrollTo("typingIndicator", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: keyboardHeight) { _, _ in
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        } else if isTyping {
                            withAnimation {
                                proxy.scrollTo("typingIndicator", anchor: .bottom)
                            }
                        }
                    }
                    // When tapping outside text field, dismiss keyboard
                    .onTapGesture {
                        isInputFieldFocused = false
                    }
                }
            }
            
            // Input area - fixed at the bottom of the screen
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 12) {
                    Divider()
                        .background(AppColors.surface.opacity(0.6))
                    
                    let isMobile = horizontalSizeClass == .compact
                    
                    if isMobile {
                        HStack(spacing: 12) {
                            Button {
                                isListening.toggle()
                                if isListening {
                                    // Implement voice recording functionality
                                }
                            } label: {
                                Image(systemName: isListening ? "mic.fill" : "mic")
                                    .font(.system(size: 22))
                                    .foregroundColor(isListening ? AppColors.success : AppColors.textMuted)
                                    .padding(8)
                                    .background(
                                        Circle()
                                            .fill(AppColors.surface.opacity(0.8))
                                            .shadow(color: isListening ? AppColors.success.opacity(0.5) : .clear, radius: 5)
                                    )
                            }

                            // Text field
                            TextField("Ask me anything...", text: $userInput)
                                .focused($isInputFieldFocused)
                                .padding(12)
                                .background(AppColors.surface)
                                .cornerRadius(25)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 25)
                                        .stroke(AppColors.textMuted.opacity(0.4), lineWidth: 1)
                                )
                                .submitLabel(.send)
                                .onSubmit {
                                    sendMessage()
                                }
                            
                            Button {
                                sendMessage()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(userInput.isEmpty ? AppColors.textMuted : AppColors.primary)
                            }
                            .disabled(userInput.isEmpty)
                        }
                    } else {
                        // Desktop layout
                        HStack(spacing: 12) {
                            Button {
                                isListening.toggle()
                                if isListening {
                                    // Implement voice recording functionality
                                }
                            } label: {
                                Image(systemName: isListening ? "mic.fill" : "mic")
                                    .font(.system(size: 20))
                                    .foregroundColor(isListening ? AppColors.success : AppColors.textMuted)
                                    .padding(10)
                                    .background(
                                        Circle()
                                            .fill(AppColors.surface.opacity(0.8))
                                            .shadow(color: isListening ? AppColors.success.opacity(0.5) : .clear, radius: 5)
                                    )
                            }
                            
                            TextField("Ask me anything...", text: $userInput)
                                .focused($isInputFieldFocused)
                                .padding(12)
                                .background(AppColors.surface)
                                .cornerRadius(25)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 25)
                                        .stroke(AppColors.textMuted.opacity(0.4), lineWidth: 1)
                                )
                                .submitLabel(.send)
                                .onSubmit {
                                    sendMessage()
                                }
                            
                            Button {
                                sendMessage()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(userInput.isEmpty ? AppColors.textMuted : AppColors.primary)
                            }
                            .disabled(userInput.isEmpty)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(
                    AppColors.background.opacity(0.95)
                        .overlay(Rectangle().stroke(AppColors.surface, lineWidth: 1).opacity(0.3))
                )
            }
            .ignoresSafeArea(.keyboard)
        }
        .onAppear {
            // Add welcome message
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTyping = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isTyping = false
                    let welcomeMessage = "Hi, I'm your AI assistant. How can I help you today?"
                    messages.append(ChatMessage(content: welcomeMessage, isUser: false))
                    speakText(welcomeMessage)
                }
            }
            
            // Setup keyboard notifications
            setupKeyboardNotifications()
        }
        .onDisappear {
            // Stop any ongoing speech when view disappears
            speechSynthesizer.stopSpeaking(at: .immediate)
            
            // Remove keyboard observers when view disappears
            removeKeyboardNotifications()
        }
    }
    
    private func setupKeyboardNotifications() {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = keyboardFrame.height
            }
        }
        
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
            keyboardHeight = 0
        }
    }
    
    private func removeKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    private func sendMessage() {
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let userMessage = ChatMessage(content: userInput, isUser: true)
        messages.append(userMessage)
        let query = userInput
        userInput = ""
        
        // Dismiss keyboard after sending message
        isInputFieldFocused = false
        
        // Simulate AI thinking
        isTyping = true
        
        // Simulate response after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 1.5...3.0)) {
            isTyping = false
            
            // Generate response based on query
            let response = generateResponse(to: query)
            messages.append(ChatMessage(content: response, isUser: false))
            
            // Speak the response
            speakText(response)
        }
    }
    
    // Function to speak text using AVSpeechSynthesizer
    private func speakText(_ text: String) {
        // Stop any ongoing speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // Configure the utterance
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US") // You can change the language or voice
        utterance.rate = 0.5 // Adjust speech rate (0.0 to 1.0)
        utterance.pitchMultiplier = 1.1 // Adjust pitch (0.5 to 2.0)
        utterance.volume = 1.0 // Volume (0.0 to 1.0)
        
        // Set up delegate to track speaking status
        speechSynthesizer.delegate = SpeechSynthesizerDelegate.shared
        
        // Update speaking state
        SpeechSynthesizerDelegate.shared.onSpeechStarted = {
            DispatchQueue.main.async {
                self.isSpeaking = true
            }
        }
        
        SpeechSynthesizerDelegate.shared.onSpeechFinished = {
            DispatchQueue.main.async {
                self.isSpeaking = false
            }
        }
        
        // Speak the text
        speechSynthesizer.speak(utterance)
    }
    
    private func generateResponse(to query: String) -> String {
        // Check for device control commands
        let lowercaseQuery = query.lowercased()
        
        // Check for light control commands
        if lowercaseQuery.contains("turn on light") || 
           lowercaseQuery.contains("open light") || 
           lowercaseQuery.contains("switch on light") ||
           lowercaseQuery.contains("light on") {
            DeviceControlService.shared.deviceToToggle = (id: 1, turnOn: true)
            return "I've turned on the light for you."
        }
        
        if lowercaseQuery.contains("turn off light") || 
           lowercaseQuery.contains("close light") || 
           lowercaseQuery.contains("switch off light") ||
           lowercaseQuery.contains("light off") ||
           lowercaseQuery.contains("off the light") ||
           lowercaseQuery.contains("turn the light off") {
            DeviceControlService.shared.deviceToToggle = (id: 1, turnOn: false)
            return "I've turned off the light for you."
        }
        
        // Check for washing machine control commands
        if lowercaseQuery.contains("turn on washing machine") || 
           lowercaseQuery.contains("start washing machine") || 
           lowercaseQuery.contains("open washing machine") ||
           lowercaseQuery.contains("washing machine on") {
            DeviceControlService.shared.deviceToToggle = (id: 2, turnOn: true)
            return "I've turned on the washing machine for you."
        }
        
        if lowercaseQuery.contains("turn off washing machine") || 
           lowercaseQuery.contains("stop washing machine") || 
           lowercaseQuery.contains("close washing machine") ||
           lowercaseQuery.contains("washing machine off") ||
           lowercaseQuery.contains("off the washing machine") ||
           lowercaseQuery.contains("turn the washing machine off") {
            DeviceControlService.shared.deviceToToggle = (id: 2, turnOn: false)
            return "I've turned off the washing machine for you."
        }
        
        // Simple response generator - in a real app, you'd connect to an AI service
        let responses = [
            "I can help you monitor your power usage more efficiently.",
            "Based on your current usage patterns, I recommend reducing consumption during peak hours.",
            "Your battery system is operating at optimal levels today.",
            "I've analyzed your data and found ways to save up to 15% on your energy bill.",
            "Would you like me to schedule a power-saving mode for tonight?",
            "I notice you've been using more power than usual. Would you like me to investigate?",
            "Your solar panels are currently generating more power than you're using. Great job!"
        ]
        
        if lowercaseQuery.contains("hello") || lowercaseQuery.contains("hi") {
            return "Hello! How can I assist you with your power management today?"
        } else if lowercaseQuery.contains("help") {
            return "I can help you with monitoring power usage, optimizing battery performance, setting up power schedules, and providing insights on your energy consumption patterns. You can also ask me to turn on/off your light or washing machine."
        } else if lowercaseQuery.contains("usage") || lowercaseQuery.contains("power") || lowercaseQuery.contains("consumption") {
            return "Your current power consumption is within normal ranges. You've used approximately 12.4 kWh today, which is about 15% less than your weekly average."
        } else {
            return responses.randomElement() ?? "I'm here to help you manage your power usage more effectively."
        }
    }
}

// Speech Synthesizer Delegate to track speech state
class SpeechSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechSynthesizerDelegate()
    
    var onSpeechStarted: (() -> Void)?
    var onSpeechFinished: (() -> Void)?
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onSpeechStarted?()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onSpeechFinished?()
    }
}

// Chat components
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp = Date()
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        return lhs.id == rhs.id && 
               lhs.content == rhs.content && 
               lhs.isUser == rhs.isUser
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                Text(message.content)
                    .padding(12)
                    .background(AppColors.primary.opacity(0.8))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppColors.primary, lineWidth: 1)
                    )
                    .padding(.leading, 60)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 24))
                        .foregroundColor(AppColors.primary)
                    
                    Text(message.content)
                        .padding(12)
                        .background(AppColors.surface)
                        .foregroundColor(AppColors.text)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(AppColors.textMuted.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding(.trailing, 60)
                Spacer()
            }
        }
    }
}

struct TypingIndicator: View {
    @State private var firstDotOpacity: Double = 0.3
    @State private var secondDotOpacity: Double = 0.3
    @State private var thirdDotOpacity: Double = 0.3
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(AppColors.primary)
                .frame(width: 8, height: 8)
                .opacity(firstDotOpacity)
            
            Circle()
                .fill(AppColors.primary)
                .frame(width: 8, height: 8)
                .opacity(secondDotOpacity)
            
            Circle()
                .fill(AppColors.primary)
                .frame(width: 8, height: 8)
                .opacity(thirdDotOpacity)
        }
        .onAppear {
            let animation = Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
            withAnimation(animation.delay(0.0)) {
                firstDotOpacity = 1.0
            }
            withAnimation(animation.delay(0.2)) {
                secondDotOpacity = 1.0
            }
            withAnimation(animation.delay(0.4)) {
                thirdDotOpacity = 1.0
            }
        }
    }
}

// MARK: - SplineWebView for AI Assistant
struct SplineWebView: UIViewRepresentable {
    let url: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        let html = """
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body, html {
                    margin: 0;
                    padding: 0;
                    width: 100%;
                    height: 100%;
                    overflow: hidden;
                    background-color: transparent;
                }
                spline-viewer {
                    width: 100%;
                    height: 100%;
                }
            </style>
            <script type="module" src="https://unpkg.com/@splinetool/viewer@1.9.82/build/spline-viewer.js"></script>
        </head>
        <body>
            <spline-viewer url="\(url)"></spline-viewer>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
