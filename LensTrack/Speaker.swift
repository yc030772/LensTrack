import SwiftUI
import AVFoundation

// ponytail: system TTS, English only. Swap voice/language here if seniors prefer Mandarin.
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()
    @Published var speaking = false
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.playback)  // plays even with the mute switch on
    }

    func toggle(_ text: String) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate); return }
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85   // a little slower for older listeners
        synth.speak(u)
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) { speaking = true }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { speaking = false }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { speaking = false }
}

struct SpeakButton: View {
    let text: () -> String
    @ObservedObject private var speaker = Speaker.shared
    var body: some View {
        Button { speaker.toggle(text()) } label: {
            Label(speaker.speaking ? "Stop" : "Read my readings aloud",
                  systemImage: speaker.speaking ? "stop.fill" : "speaker.wave.3.fill")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 80)
        }
        .buttonStyle(.borderedProminent)
        .tint(speaker.speaking ? .red : .teal)
        .accessibilityHint("Speaks your current readings in English")
    }
}

extension Metric {
    var spokenUnit: String {
        switch self { case .iop: "millimeters of mercury"; case .glucose: "millimoles per liter"
                      case .osmolarity: "milliosmoles per liter"; case .temp: "degrees Celsius" }
    }
}

extension Store {
    var spokenSummary: String {
        let r = latest
        let parts = [Metric.glucose, .iop, .osmolarity, .temp].map { m in
            let v = m.value(r)
            let status = m.range.contains(v) ? "This is normal." : v > m.range.upperBound ? "This is above the normal range." : "This is below the normal range."
            return "Your \(m.rawValue.lowercased()) is \(m.format(v)) \(m.spokenUnit). \(status)"
        }
        let alert = conditions(.h6).first { $0.status == .alert }.map { " Attention: your \($0.name.lowercased()) indicator is on alert. Please tell your doctor." } ?? ""
        let drops = lastEyeDrops.map { " You last used eye drops at \($0.time.formatted(date: .omitted, time: .shortened))." } ?? ""
        return "Here are your latest readings. " + parts.joined(separator: " ") + alert + drops
    }

    func spokenConditions(_ w: Window) -> String {
        "Condition summary for the last \(w.rawValue.replacingOccurrences(of: " ", with: "")). " +
        conditions(w).map { "\($0.name): \($0.status.rawValue). \($0.summary)." }.joined(separator: " ")
    }
}
