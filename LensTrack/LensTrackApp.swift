import SwiftUI

@main
struct LensTrackApp: App {
    @StateObject private var store = Store.shared
    var body: some Scene {
        WindowGroup {
            Group {
                if store.paired { MainTabs() } else { Onboarding() }
            }
            .environmentObject(store)
            .tint(.teal)
            .dynamicTypeSize(.xxxLarge)   // senior-friendly: bigger text app-wide
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            OverviewView().tabItem { Label("Overview", systemImage: "house") }
            TrendsView().tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            ConditionsView().tabItem { Label("Conditions", systemImage: "waveform.path.ecg") }
            HistoryView().tabItem { Label("History", systemImage: "clock") }
        }
    }
}

// MARK: - Shared bits

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }
}

struct WindowPicker: View {
    @Binding var window: Window
    var body: some View {
        Picker("Window", selection: $window) {
            ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

extension View {
    func screenBackground() -> some View {
        background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
