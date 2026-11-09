import SwiftUI

struct Reading: Identifiable {
    let id = UUID()
    let time: Date
    let glucose: Double
    let iop: Double
    let osmolarity: Double
    let temp: Double
    let manual: Bool
}

enum Metric: String, CaseIterable, Identifiable {
    case iop = "Eye pressure", glucose = "Glucose", osmolarity = "Osmolarity", temp = "Temperature"
    var id: String { rawValue }

    var unit: String {
        switch self { case .iop: "mmHg"; case .glucose: "mmol/L"; case .osmolarity: "mOsm/L"; case .temp: "°C" }
    }
    var range: ClosedRange<Double> {
        switch self { case .iop: 10...21; case .glucose: 3.9...10; case .osmolarity: 275...308; case .temp: 33.5...35.5 }
    }
    var color: Color {
        switch self { case .iop: .indigo; case .glucose: .orange; case .osmolarity: .green; case .temp: .purple }
    }
    var decimals: Int { self == .osmolarity ? 0 : 1 }
    var shortName: String { self == .temp ? "Eye temp." : rawValue }
    func value(_ r: Reading) -> Double {
        switch self { case .iop: r.iop; case .glucose: r.glucose; case .osmolarity: r.osmolarity; case .temp: r.temp }
    }
    func format(_ v: Double) -> String { String(format: "%.\(decimals)f", v) }
}

enum Window: String, CaseIterable, Identifiable {
    case h1 = "1 h", h6 = "6 h", h24 = "24 h"
    var id: String { rawValue }
    var seconds: TimeInterval { switch self { case .h1: 3600; case .h6: 6 * 3600; case .h24: 24 * 3600 } }
}

enum Status: String { case normal = "Normal", watch = "Watch", alert = "Alert"
    var color: Color { switch self { case .normal: .green; case .watch: .orange; case .alert: .red } }
}

struct Condition: Identifiable {
    let name: String, status: Status, summary: String, threshold: String
    var id: String { name }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    @Published var events: [Event] = Store.loadEvents() { didSet { saveEvents() } }
    @Published var readings: [Reading] = []
    @Published var paired = false
    @Published var now = Date()
    @Published var lastSync = Date()
    let record = "PT-0001"
    let lens = "L-204"
    private var timer: Timer?
    private var state = (g: 5.6, i: 18.0, o: 300.0, t: 34.5)

    init() {
        // ponytail: fake data only, 24 h of 1‑min readings via mean-reverting random walk
        let start = Date().addingTimeInterval(-24 * 3600)
        for m in 0...1440 {
            let t = start.addingTimeInterval(Double(m) * 60)
            readings.append(next(at: t))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        now = Date()
        readings.append(next(at: now))
        lastSync = now
    }

    private func next(at t: Date) -> Reading {
        let h = max(0, -t.timeIntervalSinceNow / 3600)   // hours ago
        let target = (
            g: 5.6 + 1.2 * sin(h * 0.5 + 1),
            i: h < 2.5 ? 17 + (2.5 - h) * 2.3 : 17 + 2.5 * sin(h * 0.9),
            o: 301 + 6 * sin(h * 0.7),
            t: 34.5 + 0.4 * sin(h * 0.3)
        )
        func step(_ v: inout Double, _ tgt: Double, _ noise: Double) { v += 0.3 * (tgt - v) + .random(in: -noise...noise) }
        step(&state.g, target.g, 0.08); step(&state.i, target.i, 0.25)
        step(&state.o, target.o, 0.8); step(&state.t, target.t, 0.05)
        let manual = Int(t.timeIntervalSince1970 / 60) % 180 == 0
        return Reading(time: t, glucose: state.g, iop: state.i, osmolarity: state.o, temp: state.t, manual: manual)
    }

    var latest: Reading { readings.last! }

    func readings(in w: Window) -> [Reading] {
        let cutoff = now.addingTimeInterval(-w.seconds)
        return readings.filter { $0.time >= cutoff }
    }

    func stats(_ m: Metric, _ w: Window) -> (mean: Double, peak: Double, low: Double, lowAt: Date, peakAt: Date, swing: Double) {
        let rs = readings(in: w)
        let vals = rs.map(m.value)
        let mean = vals.reduce(0, +) / Double(max(vals.count, 1))
        let peakI = vals.indices.max { vals[$0] < vals[$1] } ?? 0
        let lowI = vals.indices.min { vals[$0] < vals[$1] } ?? 0
        return (mean, vals[peakI], vals[lowI], rs[lowI].time, rs[peakI].time, vals[peakI] - vals[lowI])
    }

    func conditions(_ w: Window) -> [Condition] {
        let rs = readings(in: w)
        let n = Double(max(rs.count, 1))
        let iop = stats(.iop, w)
        let above21 = rs.filter { $0.iop > 21 }.count
        let glaucoma: Status = above21 > 10 || iop.swing > 6 ? .alert : above21 > 0 ? .watch : .normal

        let osm = stats(.osmolarity, w)
        let osmHigh = Double(rs.filter { $0.osmolarity > 308 }.count) / n
        let dryEye: Status = osm.mean > 308 || osmHigh > 0.25 ? .watch : .normal

        let glu = stats(.glucose, w)
        let inRange = Double(rs.filter { Metric.glucose.range.contains($0.glucose) }.count) / n
        let diabetes: Status = inRange < 0.7 || rs.contains { $0.glucose < 3.9 } ? .alert : .normal

        let temp = stats(.temp, w)
        let inflam: Status = temp.mean > 35.5 ? .alert : .normal

        return [
            Condition(name: "Glaucoma", status: glaucoma,
                      summary: "Mean \(f1(iop.mean)) · Peak \(f1(iop.peak)) · Swing \(f1(iop.swing)) mmHg",
                      threshold: "Threshold: IOP > 21 mmHg or swing > 6 mmHg."),
            Condition(name: "Dry eye", status: dryEye,
                      summary: "Mean \(Int(osm.mean)) mOsm/L · \(Int(osmHigh * 100))% of readings > 308",
                      threshold: "Threshold: mean > 308, or > 25% of readings above 308."),
            Condition(name: "Diabetes", status: diabetes,
                      summary: "Mean \(f1(glu.mean)) mmol/L · \(Int(inRange * 100))% in range 3.9–10",
                      threshold: "Threshold: under 70% in range, or any value < 3.9."),
            Condition(name: "Ocular surface inflammation", status: inflam,
                      summary: "Mean \(f1(temp.mean)) °C · Peak \(f1(temp.peak)) °C",
                      threshold: "Threshold: mean temperature > 35.5 °C."),
        ]
    }

    var csv: String {
        "time,glucose_mmol_L,iop_mmHg,osmolarity_mOsm_L,temp_C,source\n" +
        readings.map { "\($0.time.ISO8601Format()),\(f1($0.glucose)),\(f1($0.iop)),\(Int($0.osmolarity)),\(f1($0.temp)),\($0.manual ? "manual" : "lens")" }
            .joined(separator: "\n")
    }
}

func f1(_ v: Double) -> String { String(format: "%.1f", v) }

extension Date {
    var hm: String { formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()) }
    var hms: String { formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second()) }
}
