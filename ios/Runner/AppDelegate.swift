import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var volumeObserver: NSKeyValueObservation?
  private var audioSession: AVAudioSession?
  private var eventSink: FlutterEventSink?
  private var lastTriggerTime: Date?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Volume button event channel kur
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

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events

    audioSession = AVAudioSession.sharedInstance()
    try? audioSession?.setActive(true)

    lastVolume = audioSession?.outputVolume ?? 0.5

    volumeObserver = audioSession?.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
      guard let self = self else { return }
      let newVolume = session.outputVolume

      // Volume UP basıldı
      if newVolume > self.lastVolume {
        let now = Date()
        // 3 saniye debounce
        if let last = self.lastTriggerTime, now.timeIntervalSince(last) < 3.0 {
          self.lastVolume = newVolume
          return
        }
        self.lastTriggerTime = now
        DispatchQueue.main.async {
          self.eventSink?("volume_up")
        }
      }
      self.lastVolume = newVolume
    }

    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    volumeObserver?.invalidate()
    volumeObserver = nil
    eventSink = nil
    return nil
  }
}
