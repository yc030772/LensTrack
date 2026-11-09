import SwiftUI

struct Onboarding: View {
    @State private var scanned = false
    var body: some View {
        NavigationStack {
            ScanView(scanned: $scanned)
                .navigationDestination(isPresented: $scanned) { PairView() }
        }
    }
}

struct ScanView: View {
    @Binding var scanned: Bool
    @State private var pulse = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("STEP 1 OF 2").font(.caption.weight(.bold)).foregroundStyle(.teal)
            Text("Connect your record").font(.title.bold())
            Text("Scan the QR code from your clinic. It opens an anonymous record that holds no names.")
                .foregroundStyle(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.11, green: 0.15, blue: 0.19))
                VStack(spacing: 18) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 120)).foregroundStyle(.white)
                        .overlay(Rectangle().fill(.teal).frame(height: 2).offset(y: pulse ? 60 : -60))
                    Text("Fit the code inside the frame").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [60, 130]))
                    .foregroundStyle(.white).padding(24)
            }
            .frame(height: 260).padding(.top, 8)
            .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever()) { pulse.toggle() } }

            Text("The code is detected automatically. Camera access is required.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Enter code manually") { scanned = true }
                .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
        }
        .padding(20)
        .screenBackground()
        .task {  // ponytail: fake camera — "detects" the code after 3 s
            try? await Task.sleep(for: .seconds(3))
            scanned = true
        }
    }
}

struct PairView: View {
    @EnvironmentObject var store: Store
    @State private var selected = "L-204"
    private let devices = [("L-204", "Right eye · Battery 82%", "Strong signal", Color.green),
                           ("L-198", "Left eye · Battery 41%", "Weak signal", Color.orange)]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("STEP 2 OF 2").font(.caption.weight(.bold)).foregroundStyle(.teal)
            Text("Pair your smart lens").font(.title.bold())

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle").foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Record \(store.record) verified").font(.subheadline.weight(.semibold))
                    Text("Code issued by your clinic · anonymous").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            Text("NEARBY DEVICES").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            ForEach(devices, id: \.0) { d in
                Button { selected = d.0 } label: {
                    HStack {
                        Image(systemName: "circle.circle").foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LensTrack \(d.0)").font(.subheadline.weight(.semibold))
                            Text(d.1).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Pill(text: d.2, color: d.3)
                    }
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected == d.0 ? Color.teal : Color(.separator), lineWidth: selected == d.0 ? 2 : 1))
                }
                .buttonStyle(.plain)
            }

            Text("HOW TO PAIR").font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(.top, 6)
            ForEach(Array(["Put the lens in and blink a few times to wake it.",
                           "Hold your phone within 1 metre of your eye.",
                           "Select your lens, then tap Pair."].enumerated()), id: \.offset) { i, s in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)").font(.caption.weight(.bold)).frame(width: 20, height: 20)
                        .background(Color(.tertiarySystemFill), in: Circle())
                    Text(s).font(.subheadline)
                }
            }
            Spacer()
            Button("Pair \(selected)") { store.paired = true }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
        }
        .padding(20)
        .screenBackground()
        .navigationBarBackButtonHidden()
    }
}
