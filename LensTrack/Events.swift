import SwiftUI
import Speech
import AppIntents

// MARK: - Model

enum EventKind: String, Codable, CaseIterable {
    case eyeDrops = "Eye drops", meal = "Meal", medication = "Medication"
    var icon: String { switch self { case .eyeDrops: "💧"; case .meal: "🍚"; case .medication: "💊" } }

    /// ponytail: keyword match, zh + en. Order matters: 眼藥/藥水 before 藥.
    static func parse(_ s: String) -> EventKind? {
        let t = s.lowercased()
        if ["drop", "眼藥", "藥水", "眼药", "药水"].contains(where: t.contains) { return .eyeDrops }
        if ["meal", "eat", "ate", "lunch", "dinner", "breakfast", "food", "吃", "餐", "飯", "饭"].contains(where: t.contains) { return .meal }
        if ["medic", "pill", "tablet", "藥", "药"].contains(where: t.contains) { return .medication }
        return nil
    }
}

struct Event: Identifiable, Codable {
    var id = UUID()
    let time: Date
    let kind: EventKind
}

extension Store {
    private static let key = "events"

    static func loadEvents() -> [Event] {
        // ponytail: UserDefaults JSON. Move to SwiftData if events grow past a few thousand.
        (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([Event].self, from: $0) } ?? []
    }
    func saveEvents() {
        UserDefaults.standard.set(try? JSONEncoder().encode(events), forKey: Store.key)
    }
    @discardableResult
    func log(_ kind: EventKind, at time: Date = .now) -> Event {
        let e = Event(time: time, kind: kind)
        events.append(e)
        return e
    }
    func events(in w: Window) -> [Event] {
        let cutoff = now.addingTimeInterval(-w.seconds)
        return events.filter { $0.time >= cutoff }
    }
    var lastEyeDrops: Event? { events.last { $0.kind == .eyeDrops } }
}

// MARK: - Voice input

@MainActor
final class Recorder: ObservableObject {
    @Published var listening = false
    @Published var transcript = ""
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var onResult: ((String) -> Void)?

    func toggle(onResult: @escaping (String) -> Void) {
        if listening { stop() } else { Task { await start(onResult: onResult) } }
    }

    private func start(onResult: @escaping (String) -> Void) async {
        guard await AVAudioApplication.requestRecordPermission(), await Self.speechAuthorized() else { return }
        self.onResult = onResult
        transcript = ""
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement)
        try? session.setActive(true)
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in req.append(buf) }
        engine.prepare()
        guard (try? engine.start()) != nil else { return }
        task = recognizer.recognitionTask(with: req) { [weak self] res, err in
            Task { @MainActor in
                guard let self, self.listening else { return }
                if let res { self.transcript = res.bestTranscription.formattedString }
                if err != nil || res?.isFinal == true { self.stop() }
            }
        }
        listening = true
        Task { try? await Task.sleep(for: .seconds(6)); if listening { stop() } }  // auto-stop
    }

    private func stop() {
        guard listening else { return }
        listening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        try? AVAudioSession.sharedInstance().setCategory(.playback)   // hand back to TTS
        onResult?(transcript)
    }

    private static func speechAuthorized() async -> Bool {
        await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
    }
}

struct EventButtons: View {
    @EnvironmentObject var store: Store
    @StateObject private var rec = Recorder()

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { confirm(store.log(.eyeDrops)) } label: {
                    Label("I used eye drops", systemImage: "drop.fill")
                        .font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 80)
                }
                .buttonStyle(.bordered).tint(.blue)

                Button { rec.toggle { heard($0) } } label: {
                    Label(rec.listening ? "Listening…" : "Speak", systemImage: rec.listening ? "waveform" : "mic.fill")
                        .font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 80)
                }
                .buttonStyle(.borderedProminent).tint(rec.listening ? .red : .teal)
                .accessibilityHint("Say eye drops, meal, or medication")
            }
            if rec.listening || !rec.transcript.isEmpty {
                Text(rec.transcript.isEmpty ? "Say “eye drops”, “meal” or “medication”" : "“\(rec.transcript)”")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let e = store.lastEyeDrops {
                Text("Last eye drops: \(e.time.hm)").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func heard(_ text: String) {
        if let kind = EventKind.parse(text) { confirm(store.log(kind)) }
        else { Speaker.shared.toggle("Sorry, I did not catch that. Please say eye drops, meal, or medication.") }
    }
    private func confirm(_ e: Event) {
        Speaker.shared.toggle("\(e.kind.rawValue) logged at \(e.time.formatted(date: .omitted, time: .shortened)).")
    }
}

// MARK: - Siri

struct LogEyeDropsIntent: AppIntent {
    static var title: LocalizedStringResource = "Log eye drops"
    static var description = IntentDescription("Records that you used eye drops now.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let e = Store.shared.log(.eyeDrops)
        return .result(dialog: "Eye drops logged at \(e.time.formatted(date: .omitted, time: .shortened)).")
    }
}

struct LensTrackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogEyeDropsIntent(),
                    phrases: ["Log eye drops in \(.applicationName)",
                              "I used eye drops in \(.applicationName)",
                              "\(.applicationName) eye drops",
                              "用 \(.applicationName) 記錄眼藥水",
                              "\(.applicationName) 點眼藥水"],
                    shortTitle: "Log eye drops", systemImageName: "drop.fill")
    }
}
