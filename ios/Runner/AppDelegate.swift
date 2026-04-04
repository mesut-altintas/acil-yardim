import Flutter
import UIKit
import AVFoundation
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let eventChannel = FlutterEventChannel(
      name: "com.acilyardim/volume_button",
      binaryMessenger: controller.binaryMessenger
    )
    eventChannel.setStreamHandler(VolumeButtonHandler())

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

class VolumeButtonHandler: NSObject, FlutterStreamHandler {
  private var volumeObserver: NSKeyValueObservation?
  private var eventSink: FlutterEventSink?
  private var lastVolume: Float = 0.5
  private var lastTriggerTime: Date?
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

      if newVolume > self.lastVolume {
        let now = Date()
        if let last = self.lastTriggerTime, now.timeIntervalSince(last) < 3.0 {
          self.resetVolume()
          self.lastVolume = 0.5
          return
        }
        self.lastTriggerTime = now
        self.resetVolume()
        self.lastVolume = 0.5
        DispatchQueue.main.async {
          self.eventSink?("volume_up")
        }
      } else {
        self.lastVolume = newVolume
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

    // 1 saniyelik sessiz buffer oluştur ve döngüye al
    let frameCount = AVAudioFrameCount(44100)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
    buffer.frameLength = frameCount
    // Buffer sıfırlanmış gelir (sessizlik)

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
