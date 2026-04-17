import SwiftUI
import WatchConnectivity

// WatchConnectivity oturumunu yönetir ve iPhone'a mesaj gönderir
class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    @Published var lastResult: TriggerResult = .idle
    @Published var isReachable: Bool = false

    enum TriggerResult {
        case idle
        case sending
        case success(String)
        case error(String)
    }

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // iPhone'a tetikleme mesajı gönder
    func send(type: String) {
        guard WCSession.default.isReachable else {
            lastResult = .error("iPhone erişilemiyor")
            return
        }
        lastResult = .sending
        WCSession.default.sendMessage(["trigger": type], replyHandler: { reply in
            DispatchQueue.main.async {
                let status = reply["status"] as? String ?? "ok"
                self.lastResult = .success(status == "ok" ? "Gönderildi ✓" : status)
            }
        }, errorHandler: { error in
            DispatchQueue.main.async {
                self.lastResult = .error("Hata: \(error.localizedDescription)")
            }
        })
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }
}

struct ContentView: View {
    @StateObject private var session = WatchSessionManager.shared
    @State private var confirmType: String? = nil   // Onay bekleyen tetikleme türü
    @State private var resultTimer: Timer? = nil

    var body: some View {
        if let type = confirmType {
            // Onay ekranı — yanlışlıkla basışı önler
            ConfirmView(type: type) {
                triggerWith(type: type)
                confirmType = nil
            } onCancel: {
                confirmType = nil
            }
        } else {
            mainView
        }
    }

    // Ana ekran: ACİL + GÜVENDEYİM
    var mainView: some View {
        VStack(spacing: 10) {
            // Durum göstergesi
            statusBadge

            // ACİL butonu
            Button(action: { confirmType = "emergency" }) {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 22))
                    Text("ACİL")
                        .font(.system(size: 14, weight: .black))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.9, green: 0.22, blue: 0.27))  // #E63946

            // GÜVENDEYİM butonu
            Button(action: { confirmType = "safe" }) {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 20))
                    Text("GÜVENDEYİM")
                        .font(.system(size: 11, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.18, green: 0.8, blue: 0.44))  // #2ECC71
        }
        .padding(.horizontal, 6)
    }

    // Durum rozeti
    @ViewBuilder
    var statusBadge: some View {
        switch session.lastResult {
        case .idle:
            if !session.isReachable {
                Text("iPhone bağlı değil")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
        case .sending:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.7)
                Text("Gönderiliyor...")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
            }
        case .success(let msg):
            Text(msg)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.green)
        case .error(let msg):
            Text(msg)
                .font(.system(size: 9))
                .foregroundColor(.orange)
                .multilineTextAlignment(.center)
        }
    }

    // Tetikle ve 3 sn sonra idle'a dön
    func triggerWith(type: String) {
        WKInterfaceDevice.current().play(type == "emergency" ? .failure : .success)
        session.send(type: type)
        resultTimer?.invalidate()
        resultTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            DispatchQueue.main.async {
                session.lastResult = .idle
            }
        }
    }
}

// Onay ekranı — yanlış basışı önler
struct ConfirmView: View {
    let type: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var isEmergency: Bool { type == "emergency" }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isEmergency ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                .font(.system(size: 28))
                .foregroundColor(isEmergency ? Color(red: 0.9, green: 0.22, blue: 0.27) : Color(red: 0.18, green: 0.8, blue: 0.44))

            Text(isEmergency ? "ACİL gönderilsin mi?" : "Güvende olduğunu bildir?")
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button("İptal", action: onCancel)
                    .buttonStyle(.bordered)
                    .tint(.gray)
                    .font(.system(size: 12))

                Button("Gönder", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(isEmergency ? Color(red: 0.9, green: 0.22, blue: 0.27) : Color(red: 0.18, green: 0.8, blue: 0.44))
                    .font(.system(size: 12, weight: .bold))
            }
        }
        .padding(.horizontal, 4)
    }
}
