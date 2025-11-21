import SwiftUI
import Combine
import UserNotifications
import AVFoundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Audio Mode
enum AudioMode: String, CaseIterable {
    case soundOnly = "Sound Only"
    case soundAndVoice = "Sound + Voice"

    var icon: String {
        switch self {
        case .soundOnly: return "speaker.wave.2.fill"
        case .soundAndVoice: return "person.wave.2.fill"
        }
    }
}

// MARK: - Language
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case spanish = "es"

    var displayName: String {
        switch self {
        case .english: return "EN"
        case .spanish: return "ES"
        }
    }

    var voiceIdentifier: String {
        switch self {
        case .english: return "en-US"
        case .spanish: return "es-ES"
        }
    }
}

// MARK: - Website Blocker Manager
class WebsiteBlockerManager: ObservableObject {
    static let shared = WebsiteBlockerManager()

    @Published var whitelist: [String] = [] {
        didSet {
            saveWhitelist()
        }
    }
    @Published var isBlocking: Bool = false
    @Published var isAuthorized: Bool = false

    private let hostsPath = "/etc/hosts"
    private let markerStart = "# POMOFANTASY START"
    private let markerEnd = "# POMOFANTASY END"

    // Common distracting sites to block by default
    let defaultBlockList: [String] = [
        "facebook.com", "www.facebook.com",
        "twitter.com", "www.twitter.com", "x.com", "www.x.com",
        "instagram.com", "www.instagram.com",
        "youtube.com", "www.youtube.com",
        "tiktok.com", "www.tiktok.com",
        "reddit.com", "www.reddit.com",
        "netflix.com", "www.netflix.com",
        "twitch.tv", "www.twitch.tv"
    ]

    init() {
        loadWhitelist()
    }

    private func loadWhitelist() {
        if let saved = UserDefaults.standard.stringArray(forKey: "pomofantasy_whitelist") {
            whitelist = saved
        }
    }

    private func saveWhitelist() {
        UserDefaults.standard.set(whitelist, forKey: "pomofantasy_whitelist")
    }

    func addToWhitelist(_ site: String) {
        let cleaned = site.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
        if !cleaned.isEmpty && !whitelist.contains(cleaned) {
            whitelist.append(cleaned)
        }
    }

    func removeFromWhitelist(_ site: String) {
        whitelist.removeAll { $0 == site }
    }

    // Request authorization once via AppleScript - macOS caches it for about 5 minutes
    func requestAuthorization() -> Bool {
        if isAuthorized {
            return true
        }

        // Simple auth test - just run a harmless command to trigger password prompt
        let script = "do shell script \"echo authorized\" with administrator privileges"

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if error == nil && result.stringValue == "authorized" {
                isAuthorized = true
                return true
            }
        }
        return false
    }

    func enableBlocking() {
        let sitesToBlock = defaultBlockList.filter { site in
            let baseDomain = site.replacingOccurrences(of: "www.", with: "")
            return !whitelist.contains(baseDomain) && !whitelist.contains(site)
        }

        guard !sitesToBlock.isEmpty else {
            isBlocking = true
            return
        }

        // First request authorization if not done
        if !isAuthorized {
            _ = requestAuthorization()
        }

        var blockEntries = "\\n\(markerStart)\\n"
        for site in sitesToBlock {
            blockEntries += "127.0.0.1 \(site)\\n"
        }
        blockEntries += "\(markerEnd)\\n"

        let command = "echo '\(blockEntries)' | sudo tee -a \(hostsPath) > /dev/null && sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder 2>/dev/null || true"

        let script = "do shell script \"\(command)\" with administrator privileges"

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if error == nil {
                isBlocking = true
                isAuthorized = true // Remember we're authorized now
            }
        }
    }

    func disableBlocking() {
        guard isBlocking else { return }

        let command = "sed -i '' '/\(markerStart)/,/\(markerEnd)/d' \(hostsPath) && dscacheutil -flushcache && killall -HUP mDNSResponder 2>/dev/null || true"

        let script = "do shell script \"\(command)\" with administrator privileges"

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if error == nil {
                isBlocking = false
            }
        }
    }
}

// MARK: - Audio Manager
class AudioManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AudioManager()

    @Published var audioMode: AudioMode = .soundAndVoice
    @Published var language: AppLanguage = .english
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // Localized messages
    private func localizedMessage(_ key: String) -> String {
        let messages: [String: [AppLanguage: String]] = [
            "start": [
                .english: "Focus time started. Let's go!",
                .spanish: "Tiempo de enfoque iniciado. ¡Vamos!"
            ],
            "pause": [
                .english: "Timer paused",
                .spanish: "Temporizador pausado"
            ],
            "resume": [
                .english: "Timer resumed",
                .spanish: "Temporizador reanudado"
            ],
            "workComplete": [
                .english: "Great work! Time for a break.",
                .spanish: "¡Buen trabajo! Es hora de descansar."
            ],
            "breakComplete": [
                .english: "Break is over. Ready to focus?",
                .spanish: "El descanso terminó. ¿Listo para enfocarte?"
            ]
        ]
        return messages[key]?[language] ?? ""
    }

    // System sounds
    func playStartSound() {
        NSSound(named: "Blow")?.play()
        if audioMode == .soundAndVoice {
            speak(localizedMessage("start"))
        }
    }

    func playPauseSound() {
        NSSound(named: "Pop")?.play()
        if audioMode == .soundAndVoice {
            speak(localizedMessage("pause"))
        }
    }

    func playResumeSound() {
        NSSound(named: "Pop")?.play()
        if audioMode == .soundAndVoice {
            speak(localizedMessage("resume"))
        }
    }

    func playWorkCompleteSound() {
        NSSound(named: "Glass")?.play()
        if audioMode == .soundAndVoice {
            speak(localizedMessage("workComplete"))
        }
    }

    func playBreakCompleteSound() {
        NSSound(named: "Hero")?.play()
        if audioMode == .soundAndVoice {
            speak(localizedMessage("breakComplete"))
        }
    }

    func playResetSound() {
        NSSound(named: "Tink")?.play()
    }

    func playSkipSound() {
        NSSound(named: "Morse")?.play()
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.voiceIdentifier)
        utterance.rate = 0.5
        utterance.volume = 0.8
        synthesizer.speak(utterance)
    }
}

struct MiniPomodoroApp: App {
    @StateObject private var timerManager = TimerManager()

    var body: some Scene {
        // This creates the Menu Bar Item
        MenuBarExtra {
            // The Custom "Little Interface" View
            PomodoroView(manager: timerManager)
        } label: {
            // The icon/text shown in the status bar
            HStack(spacing: 4) {
                Image(systemName: timerManager.mode == .work ? "brain.head.profile" : "cup.and.saucer.fill")
                // Only show time in menu bar if timer is running to save space, or always:
                Text(timerManager.timeString)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window) // This makes it a custom popover, not a standard list
    }
}


class TimerManager: ObservableObject {
    enum Mode {
        case work
        case shortBreak

        var duration: Int {
            switch self {
            case .work: return 25 * 60
            case .shortBreak: return 5 * 60
            }
        }

        var color: Color {
            switch self {
            case .work: return .red
            case .shortBreak: return .green
            }
        }

        var title: String {
            switch self {
            case .work: return "Focus"
            case .shortBreak: return "Break"
            }
        }
    }

    @Published var mode: Mode = .work
    @Published var secondsLeft: Int = 25 * 60
    @Published var isRunning: Bool = false
    @Published var progress: CGFloat = 1.0
    @Published var blockingEnabled: Bool = false

    private var timer: Timer?
    private let audioManager = AudioManager.shared
    private let websiteBlocker = WebsiteBlockerManager.shared
    private var hasStartedOnce = false

    init() {
        requestNotificationPermission()
    }

    func start() {
        let wasRunning = hasStartedOnce && !isRunning
        isRunning = true

        if !hasStartedOnce {
            hasStartedOnce = true
            audioManager.playStartSound()
            // Enable blocking when starting work mode
            if mode == .work && blockingEnabled {
                websiteBlocker.enableBlocking()
            }
        } else if wasRunning {
            audioManager.playResumeSound()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if self.secondsLeft > 0 {
                self.secondsLeft -= 1
                self.updateProgress()
            } else {
                self.timerCompleted()
            }
        }
    }

    func stop() {
        if isRunning {
            audioManager.playPauseSound()
        }
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        let wasRunning = isRunning
        if wasRunning {
            timer?.invalidate()
            timer = nil
            isRunning = false
        }
        audioManager.playResetSound()
        secondsLeft = mode.duration
        progress = 1.0
        hasStartedOnce = false
    }

    func toggleMode() {
        audioManager.playSkipSound()
        timer?.invalidate()
        timer = nil
        isRunning = false

        let previousMode = mode
        mode = (mode == .work) ? .shortBreak : .work
        secondsLeft = mode.duration
        progress = 1.0
        hasStartedOnce = false

        // Handle blocking based on mode change
        if blockingEnabled {
            if previousMode == .work && mode == .shortBreak {
                // Switching to break - disable blocking
                websiteBlocker.disableBlocking()
            } else if previousMode == .shortBreak && mode == .work {
                // Switching to work - enable blocking
                websiteBlocker.enableBlocking()
            }
        }
    }

    func endSession() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        mode = .work
        secondsLeft = mode.duration
        progress = 1.0
        hasStartedOnce = false

        // Always disable blocking when ending session
        if websiteBlocker.isBlocking {
            websiteBlocker.disableBlocking()
        }

        audioManager.playResetSound()
    }

    private func timerCompleted() {
        timer?.invalidate()
        timer = nil
        isRunning = false

        let previousMode = mode

        if mode == .work {
            audioManager.playWorkCompleteSound()
        } else {
            audioManager.playBreakCompleteSound()
        }

        sendNotification()
        mode = (mode == .work) ? .shortBreak : .work
        secondsLeft = mode.duration
        progress = 1.0
        hasStartedOnce = false

        // Handle blocking based on mode change
        if blockingEnabled {
            if previousMode == .work && mode == .shortBreak {
                websiteBlocker.disableBlocking()
            } else if previousMode == .shortBreak && mode == .work {
                websiteBlocker.enableBlocking()
            }
        }
    }

    private func updateProgress() {
        withAnimation {
            progress = CGFloat(secondsLeft) / CGFloat(mode.duration)
        }
    }

    var timeString: String {
        let m = secondsLeft / 60
        let s = secondsLeft % 60
        return String(format: "%02d:%02d", m, s)
    }

    // Notification Logic
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Timer Finished!"
        content.body = mode == .work ? "Time for a break." : "Back to work!"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - 3. The Custom Interface View
struct PomodoroView: View {
    @ObservedObject var manager: TimerManager
    @ObservedObject var audioManager = AudioManager.shared
    @ObservedObject var websiteBlocker = WebsiteBlockerManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showSettings = false
    @State private var newSite = ""

    var body: some View {
        VStack(spacing: 12) {

            // Header with controls
            HStack {
                Text(manager.mode.title.uppercased())
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                Spacer()

                // Language Button
                Button(action: {
                    audioManager.language = audioManager.language == .english ? .spanish : .english
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: "globe")
                            .font(.caption)
                        Text(audioManager.language.displayName)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                // Audio Mode Button
                Button(action: {
                    audioManager.audioMode = audioManager.audioMode == .soundOnly ? .soundAndVoice : .soundOnly
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: audioManager.audioMode.icon)
                            .font(.caption)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                // Settings Button
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape.fill")
                        .font(.caption)
                        .padding(6)
                        .background(showSettings ? Color.orange.opacity(0.3) : Color.secondary.opacity(0.2))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            if showSettings {
                // Settings Panel
                VStack(spacing: 10) {
                    // Authorization status & button
                    HStack {
                        Image(systemName: websiteBlocker.isAuthorized ? "checkmark.shield.fill" : "lock.shield")
                            .foregroundColor(websiteBlocker.isAuthorized ? .green : .orange)
                        Text(websiteBlocker.isAuthorized
                             ? (audioManager.language == .english ? "Authorized" : "Autorizado")
                             : (audioManager.language == .english ? "Not Authorized" : "No Autorizado"))
                            .font(.system(size: 11))
                        Spacer()
                        if !websiteBlocker.isAuthorized {
                            Button(action: {
                                _ = websiteBlocker.requestAuthorization()
                            }) {
                                Text(audioManager.language == .english ? "Authorize" : "Autorizar")
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.3))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()

                    // Block websites toggle
                    HStack {
                        Image(systemName: manager.blockingEnabled ? "shield.fill" : "shield")
                            .foregroundColor(manager.blockingEnabled ? .green : .secondary)
                        Text(audioManager.language == .english ? "Block Sites" : "Bloquear Sitios")
                            .font(.system(size: 11))
                        Spacer()
                        Toggle("", isOn: $manager.blockingEnabled)
                            .toggleStyle(.switch)
                            .scaleEffect(0.7)
                    }

                    Divider()

                    // Whitelist section
                    VStack(alignment: .leading, spacing: 6) {
                        Text(audioManager.language == .english ? "Allowed Sites (Whitelist)" : "Sitios Permitidos")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        // Add site input
                        HStack {
                            TextField(audioManager.language == .english ? "Add site..." : "Añadir sitio...", text: $newSite)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                            Button(action: {
                                websiteBlocker.addToWhitelist(newSite)
                                newSite = ""
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                            .disabled(newSite.isEmpty)
                        }

                        // Whitelist items
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(websiteBlocker.whitelist, id: \.self) { site in
                                    HStack {
                                        Text(site)
                                            .font(.system(size: 10))
                                        Spacer()
                                        Button(action: {
                                            websiteBlocker.removeFromWhitelist(site)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.system(size: 12))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                        }
                        .frame(maxHeight: 80)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal, 10)
            } else {
                // Circular Timer
                ZStack {
                    Circle()
                        .stroke(lineWidth: 10)
                        .opacity(0.1)
                        .foregroundColor(manager.mode.color)

                    Circle()
                        .trim(from: 0.0, to: manager.progress)
                        .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                        .foregroundColor(manager.mode.color)
                        .rotationEffect(Angle(degrees: 270.0))
                        .animation(.linear(duration: 1.0), value: manager.progress)

                    VStack(spacing: 4) {
                        Text(manager.timeString)
                            .font(.system(size: 40, weight: .thin, design: .monospaced))
                            .contentTransition(.numericText(value: Double(manager.secondsLeft)))

                        if manager.blockingEnabled && manager.mode == .work {
                            HStack(spacing: 2) {
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 8))
                                Text(audioManager.language == .english ? "Blocking" : "Bloqueando")
                                    .font(.system(size: 8))
                            }
                            .foregroundColor(.green)
                        }
                    }
                }
                .frame(width: 180, height: 180)
                .padding(.horizontal, 20)
            }

            // Controls
            HStack(spacing: 30) {
                // Skip Button
                Button(action: manager.toggleMode) {
                    VStack {
                        Image(systemName: "forward.end.fill")
                            .font(.title2)
                        Text("Skip")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(.plain)
                .opacity(0.7)

                // Play / Pause Button
                Button(action: {
                    manager.isRunning ? manager.stop() : manager.start()
                }) {
                    ZStack {
                        Circle()
                            .fill(manager.mode.color)
                            .frame(width: 60, height: 60)
                            .shadow(radius: 4)

                        Image(systemName: manager.isRunning ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)

                // Reset Button
                Button(action: manager.reset) {
                    VStack {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title2)
                        Text("Reset")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(.plain)
                .opacity(0.7)
            }

            // End Session Button
            Button(action: manager.endSession) {
                HStack {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 12))
                    Text(audioManager.language == .english ? "End Session" : "Finalizar Sesión")
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.2))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .frame(width: 260, height: showSettings ? 480 : 380)
        #if os(macOS)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        #endif
    }
}

// Helper for macOS blurring background
#if os(macOS)
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
#endif

// MARK: - ContentView (main view for WindowGroup)
struct ContentView: View {
    @StateObject private var timerManager = TimerManager()

    var body: some View {
        PomodoroView(manager: timerManager)
    }
}
