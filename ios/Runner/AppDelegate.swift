import Flutter
import UIKit
import AVFoundation
import MediaPlayer
import FirebaseMessaging
import UserNotifications
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate {

  // Watch'tan gelen tetiklemeleri Flutter'a iletmek için
  private var watchChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // FCM delegate — token yenileme olaylarını yakala
    Messaging.messaging().delegate = self

    // APNs'e kayıt ol (bildirimlerin iOS'a ulaşması için zorunlu)
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound]
    ) { _, _ in }
    application.registerForRemoteNotifications()

    let controller = window?.rootViewController as! FlutterViewController

    // Ses tuşu event channel (AB Shutter 3)
    let eventChannel = FlutterEventChannel(
      name: "com.acilyardim/volume_button",
      binaryMessenger: controller.binaryMessenger
    )
    eventChannel.setStreamHandler(VolumeButtonHandler())

    // Watch tetikleme method channel
    watchChannel = FlutterMethodChannel(
      name: "com.acilyardim/watch_trigger",
      binaryMessenger: controller.binaryMessenger
    )

    // WatchConnectivity başlat
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("[FCM] iOS token: \(fcmToken ?? "nil")")
  }
}

// MARK: - WCSessionDelegate
extension AppDelegate: WCSessionDelegate {

  func session(_ session: WCSession,
               activationDidCompleteWith activationState: WCSessionActivationState,
               error: Error?) {
    print("[Watch] WCSession activated: \(activationState.rawValue)")
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}
  func sessionDidDeactivate(_ session: WCSession) {
    WCSession.default.activate()
  }

  // Watch'tan gelen mesajı al → Flutter'a ilet
  func session(_ session: WCSession,
               didReceiveMessage message: [String: Any],
               replyHandler: @escaping ([String: Any]) -> Void) {

    guard let type = message["trigger"] as? String else {
      replyHandler(["status": "error", "reason": "unknown message"])
      return
    }

    print("[Watch] Tetikleme alındı: \(type)")

    // Ana thread'de Flutter'a ilet
    DispatchQueue.main.async {
      self.watchChannel?.invokeMethod(type, arguments: nil, result: { result in
        if let error = result as? FlutterError {
          replyHandler(["status": "error", "reason": error.message ?? "flutter error"])
        } else {
          replyHandler(["status": "ok"])
        }
      })
    }
  }
}

// MARK: - VolumeButtonHandler
class VolumeButtonHandler: NSObject, FlutterStreamHandler {
  private var volumeObserver: NSKeyValueObservation?
  private var eventSink: FlutterEventSink?
  private var lastVolume: Float = 0.5
  private var volumeView: MPVolumeView?
  private var volumeSlider: UISlider?

  // Arka plan sessiz ses — ekran kilitliyken volume butonunu output'a bağlar
  private var silentEngine: AVAudioEngine?
  private var silentPlayer: AVAudioPlayerNode?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events

    // MPVolumeView — ses sıfırlamak için
    DispatchQueue.main.async {
      let vv = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
      vv.alpha = 0.01
      UIApplication.shared.windows.first?.addSubview(vv)
      self.volumeView = vv
      self.volumeSlider = vv.subviews.first(where: { $0 is UISlider }) as? UISlider
    }

    // Audio session
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, options: .mixWithOthers)
    try? session.setActive(true)

    // Sessiz arka plan sesi başlat
    startSilentAudio()

    lastVolume = session.outputVolume

    volumeObserver = session.observe(\.outputVolume, options: [.new]) { [weak self] sess, _ in
      guard let self = self else { return }
      let newVolume = sess.outputVolume

      if newVolume > self.lastVolume + 0.01 {
        self.resetVolume()
        self.lastVolume = 0.5
        DispatchQueue.main.async {
          self.eventSink?("volume_up")
        }
      } else if newVolume < self.lastVolume - 0.01 {
        self.resetVolume()
        self.lastVolume = 0.5
        DispatchQueue.main.async {
          self.eventSink?("volume_down")
        }
      }
    }

    return nil
  }

  private func startSilentAudio() {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()

    engine.attach(player)

    guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else { return }
    engine.connect(player, to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = 0.0

    let frameCount = AVAudioFrameCount(44100)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
    buffer.frameLength = frameCount

    do {
      try engine.start()
      player.scheduleBuffer(buffer, at: nil, options: .loops)
      player.play()
      self.silentEngine = engine
      self.silentPlayer = player
    } catch {
      print("[VolumeButtonHandler] Sessiz ses başlatılamadı: \(error)")
    }
  }

  private func resetVolume() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      self.volumeSlider?.value = 0.5
      self.lastVolume = 0.5
    }
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    volumeObserver?.invalidate()
    volumeObserver = nil
    eventSink = nil
    silentPlayer?.stop()
    silentEngine?.stop()
    silentPlayer = nil
    silentEngine = nil
    volumeView?.removeFromSuperview()
    volumeView = nil
    volumeSlider = nil
    return nil
  }
}
