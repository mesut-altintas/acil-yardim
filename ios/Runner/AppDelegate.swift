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
  private var audioSession: AVAudioSession?
  private var volumeObserver: NSKeyValueObservation?
  private var eventSink: FlutterEventSink?
  private var lastVolume: Float = 0.5
  private var lastTriggerTime: Date?
  private var volumeView: MPVolumeView?
  private var volumeSlider: UISlider?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events

    // MPVolumeView'i gizli ekle - ses sıfırlamak için
    DispatchQueue.main.async {
      let vv = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
      vv.alpha = 0.01
      UIApplication.shared.windows.first?.addSubview(vv)
      self.volumeView = vv
      self.volumeSlider = vv.subviews.first(where: { $0 is UISlider }) as? UISlider
    }

    audioSession = AVAudioSession.sharedInstance()
    try? audioSession?.setCategory(.playback, options: .mixWithOthers)
    try? audioSession?.setActive(true)

    lastVolume = audioSession?.outputVolume ?? 0.5

    volumeObserver = audioSession?.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
      guard let self = self else { return }
      let newVolume = session.outputVolume

      if newVolume > self.lastVolume {
        let now = Date()
        // 3 saniye debounce
        if let last = self.lastTriggerTime, now.timeIntervalSince(last) < 3.0 {
          self.resetVolume()
          self.lastVolume = 0.5
          return
        }
        self.lastTriggerTime = now

        // Ses seviyesini sıfırla ki bir sonraki basış da algılansın
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
    volumeView?.removeFromSuperview()
    volumeView = nil
    volumeSlider = nil
    return nil
  }
}
