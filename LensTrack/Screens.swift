import SwiftUI
import Charts

// MARK: - Overview

struct OverviewView: View {
    @EnvironmentObject var store: Store
    private var greeting: String {
        switch Calendar.current.component(.hour, from: store.now) {
        case 5..<12: "Good morning"; case 12..<18: "Good afternoon"; default: "Good evening"
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(store.record) · RIGHT EYE").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        Text(greeting).font(.title.bold())
                    }
                    Spacer()
                    Image(systemName: "bell.badge").foregroundStyle(.red, .primary)
                        .frame(width: 36, height: 36).background(.background, in: Circle())
                }
                HStack(spacing: 8) {
                    Pill(text: "Streaming", color: .green)
                    Text("updated \(Int(store.now.timeIntervalSince(store.lastSync))) s ago · \(store.lens)")
                        .font(.caption).foregroundStyle(.secondary)
                }

                SpeakButton { store.spokenSummary }
                EventButtons()

                if let g = store.conditions(.h6).first, g.status != .normal {
                    let rs = store.readings(in: .h6)
                    let above = rs.filter { $0.iop > 21 }.count
                    let peak = store.stats(.iop, .h6).peak
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Eye pressure above range").font(.subheadline.weight(.semibold))
                            Text("\(above) readings above 21 mmHg in the last 6 h, peak \(f1(peak)) mmHg. Tell your doctor if you have eye pain or blurred vision.")
                                .font(.caption)
                            Text("View details →").font(.caption.weight(.semibold)).foregroundStyle(.red)
                        }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }

                Text("CURRENT READINGS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach([Metric.glucose, .iop, .osmolarity, .temp]) { m in
                        MetricCard(metric: m, value: m.value(store.latest))
                    }
                }

                Card {
                    HStack(spacing: 10) {
                        Image(systemName: "circle.circle").foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lens \(store.lens)").font(.subheadline.weight(.semibold))
                            Text("Battery 82% · Strong signal · Synced \(store.lastSync.hm)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
    }
}

struct MetricCard: View {
    let metric: Metric
    let value: Double
    var body: some View {
        let ok = metric.range.contains(value)
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.shortName).font(.subheadline.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.format(value)).font(.system(size: 40, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(metric.unit).font(.caption).foregroundStyle(.secondary)
            }
            Text("Range \(metric.format(metric.range.lowerBound))–\(metric.format(metric.range.upperBound))")
                .font(.caption2).foregroundStyle(.secondary)
            Pill(text: ok ? "Normal" : "Alert", color: ok ? .green : .red)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) { metric.color.frame(width: 3).padding(.vertical, 10) }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .animation(.default, value: value)
    }
}

// MARK: - Conditions

struct ConditionsView: View {
    @EnvironmentObject var store: Store
    @State private var window: Window = .h6
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Condition tracking").font(.title.bold())
                Text("\(store.record) · last \(window.rawValue) · \(store.readings(in: window).count) readings")
                    .font(.caption).foregroundStyle(.secondary)
                WindowPicker(window: $window)
                SpeakButton { store.spokenConditions(window) }
                ForEach(store.conditions(window)) { c in
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(c.name).font(.headline)
                                Spacer()
                                Pill(text: c.status.rawValue, color: c.status.color)
                            }
                            Text(c.summary).font(.subheadline)
                            Text(c.threshold).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .overlay(alignment: .leading) { c.status.color.frame(width: 3).padding(.vertical, 12) }
                }
                Text("Thresholds are for reference only and do not replace a doctor's diagnosis.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .screenBackground()
    }
}

// MARK: - Trends

struct TrendsView: View {
    @EnvironmentObject var store: Store
    @State private var window: Window = .h6
    @State private var metric: Metric = .iop
    var body: some View {
        let rs = store.readings(in: window)
        let s = store.stats(metric, window)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Trends").font(.title.bold())
                Text("\(store.record) · \(rs.first?.time.hm ?? "") – \(store.now.hm)").font(.caption).foregroundStyle(.secondary)
                WindowPicker(window: $window)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Metric.allCases) { m in
                            Button(m.rawValue) { metric = m }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(metric == m ? m.color : Color(.tertiarySystemFill), in: Capsule())
                                .foregroundStyle(metric == m ? .white : .primary)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric.rawValue).font(.subheadline.weight(.semibold))
                                Text("\(metric.unit) · green band = \(metric.format(metric.range.lowerBound))–\(metric.format(metric.range.upperBound))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(metric.format(metric.value(store.latest)))
                                .font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(metric.color)
                                .contentTransition(.numericText())
                        }
                        Chart {
                            RectangleMark(yStart: .value("lo", metric.range.lowerBound), yEnd: .value("hi", metric.range.upperBound))
                                .foregroundStyle(.green.opacity(0.12))
                            ForEach(rs) { r in
                                LineMark(x: .value("Time", r.time), y: .value(metric.rawValue, metric.value(r)))
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(metric.color)
                            }
                            ForEach(store.events(in: window)) { e in
                                RuleMark(x: .value("Event", e.time))
                                    .foregroundStyle(.gray.opacity(0.5)).lineStyle(.init(dash: [4, 4]))
                                    .annotation(position: .top) { Text(e.kind.icon) }
                            }
                            PointMark(x: .value("t", s.lowAt), y: .value("v", s.low))
                                .foregroundStyle(metric.color)
                                .annotation(position: .bottom) {
                                    Text("Low \(metric.format(s.low)) · \(s.lowAt.hm)").font(.caption2).foregroundStyle(.secondary)
                                }
                        }
                        .chartYScale(domain: yDomain(rs))
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute()) } }
                        .frame(height: 200)
                        .animation(.default, value: metric)
                    }
                }
                HStack(spacing: 10) {
                    StatBox(title: "Mean", value: "\(metric.format(s.mean)) \(metric.unit)")
                    StatBox(title: "Peak", value: "\(metric.format(s.peak)) \(metric.unit)")
                    StatBox(title: "Swing", value: "\(metric.format(s.swing)) \(metric.unit)")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Insight").font(.subheadline.weight(.semibold))
                    Text(insight(rs, s)).font(.caption)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
        }
        .screenBackground()
    }

    private func yDomain(_ rs: [Reading]) -> ClosedRange<Double> {
        let v = rs.map(metric.value) + [metric.range.lowerBound, metric.range.upperBound]
        let pad = (v.max()! - v.min()!) * 0.1
        return (v.min()! - pad)...(v.max()! + pad)
    }

    private func insight(_ rs: [Reading], _ s: (mean: Double, peak: Double, low: Double, lowAt: Date, peakAt: Date, swing: Double)) -> String {
        let out = rs.filter { !metric.range.contains(metric.value($0)) }.count
        var text = "\(metric.rawValue) was lowest at \(s.lowAt.hm) and rose to a peak of \(metric.format(s.peak)) at \(s.peakAt.hm)."
        text += out == 0 ? " All \(rs.count) readings were inside the normal band." : " \(out) of \(rs.count) readings were outside the normal band."
        if metric == .iop, s.swing > 6 { text += " The \(f1(s.swing)) mmHg swing exceeds the 6 mmHg threshold." }
        return text
    }
}

struct StatBox: View {
    let title: String, value: String
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let rs = store.readings(in: .h6).reversed()
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("History").font(.title.bold())
                Text("\(rs.count) readings · last 6 h").font(.caption).foregroundStyle(.secondary)
                Text("Glucose · IOP · Osmolarity · Temp.").font(.caption).foregroundStyle(.secondary)

                Card {
                    HStack(spacing: 10) {
                        Image(systemName: "qrcode").foregroundStyle(.teal)
                            .frame(width: 36, height: 36).background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share with your doctor").font(.subheadline.weight(.semibold))
                            Text("Your doctor scans the code to view record \(store.record). You can revoke access at any time.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ShareLink(item: store.csv, preview: SharePreview("LensTrack \(store.record).csv")) {
                    Text("Download CSV").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)

                if !store.events.isEmpty {
                    Text("EVENTS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Card {
                        VStack(spacing: 8) {
                            ForEach(store.events.suffix(10).reversed()) { e in
                                HStack { Text(e.kind.icon); Text(e.kind.rawValue); Spacer(); Text(e.time.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }.font(.subheadline)
                            }
                        }
                    }
                }
                LazyVStack(spacing: 0) {
                    ForEach(rs.prefix(120)) { r in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.time.hms).font(.caption.monospaced())
                                Text(r.manual ? "Manual entry" : "Lens · auto").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(r.manual ? "\(f1(r.glucose)) · – · – · –"
                                 : "\(f1(r.glucose)) · \(f1(r.iop)) · \(Int(r.osmolarity)) · \(f1(r.temp))")
                                .font(.caption.monospaced())
                        }
                        .padding(.vertical, 10)
                        Divider()
                    }
                }
                .padding(.horizontal, 12)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
        }
        .screenBackground()
    }
}
