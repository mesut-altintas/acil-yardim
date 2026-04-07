package com.example.acil_yardim

import android.content.Context
import android.database.ContentObserver
import android.media.AudioManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {

    private var volumeObserver: VolumeObserver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.acilyardim/volume_button")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val observer = VolumeObserver(Handler(Looper.getMainLooper()), audioManager, events)
                    contentResolver.registerContentObserver(
                        Settings.System.CONTENT_URI, true, observer
                    )
                    volumeObserver = observer
                }

                override fun onCancel(arguments: Any?) {
                    volumeObserver?.let { contentResolver.unregisterContentObserver(it) }
                    volumeObserver = null
                }
            })
    }
}

class VolumeObserver(
    handler: Handler,
    private val audioManager: AudioManager,
    private val events: EventChannel.EventSink
) : ContentObserver(handler) {

    private var lastVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
    private val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)

    override fun onChange(selfChange: Boolean, uri: Uri?) {
        val newVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)

        if (newVolume > lastVolume) {
            lastVolume = newVolume
            // Sesi ortaya sıfırla
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxVolume / 2, 0)
            lastVolume = maxVolume / 2
            events.success("volume_up")
        } else if (newVolume < lastVolume) {
            lastVolume = newVolume
            // Sesi ortaya sıfırla
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxVolume / 2, 0)
            lastVolume = maxVolume / 2
            events.success("volume_down")
        }
    }
}
