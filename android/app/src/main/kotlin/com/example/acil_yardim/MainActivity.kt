package com.example.acil_yardim

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.telephony.SmsManager
import android.util.Log
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var localObserver: VolumeContentObserver? = null
    private var serviceReceiver: BroadcastReceiver? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.acilyardim/accessibility")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(VolumeAccessibilityService.isEnabled(this))
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.acilyardim/call")
            .setMethodCallHandler { call, result ->
                if (call.method == "dial") {
                    val phone = call.argument<String>("phone")
                    if (phone == null) {
                        result.error("INVALID", "phone zorunludur", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val intent = Intent(Intent.ACTION_CALL, android.net.Uri.parse("tel:$phone"))
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        Log.d("AcilYardim", "Otomatik arama başlatıldı: $phone")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("AcilYardim", "Arama hatası: $e")
                        result.error("CALL_ERROR", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.acilyardim/sms")
            .setMethodCallHandler { call, result ->
                if (call.method == "send") {
                    val phone = call.argument<String>("phone")
                    val message = call.argument<String>("message")
                    if (phone == null || message == null) {
                        result.error("INVALID", "phone ve message zorunludur", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            getSystemService(SmsManager::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            SmsManager.getDefault()
                        }
                        val parts = smsManager.divideMessage(message)
                        smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                        Log.d("AcilYardim", "SMS gönderildi: $phone")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("AcilYardim", "SMS hatası: $e")
                        result.error("SMS_ERROR", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.acilyardim/volume_button")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    Log.d("AcilYardim", "EventChannel onListen")
                    eventSink = events

                    // 1. Uygulama ön plandayken: direkt ContentObserver
                    val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val obs = VolumeContentObserver(Handler(Looper.getMainLooper()), audioManager) { event ->
                        runOnUiThread { events.success(event) }
                    }
                    contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, obs)
                    localObserver = obs

                    // 2. Ekran kilitliyken: VolumeService Broadcast'ini dinle
                    val receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context, intent: Intent) {
                            val event = intent.getStringExtra(VolumeService.EXTRA_EVENT) ?: return
                            Log.d("AcilYardim", "Service broadcast alındı: $event")
                            runOnUiThread {
                                try {
                                    events.success(event)
                                    Log.d("AcilYardim", "EventSink.success OK: $event")
                                } catch (e: Exception) {
                                    Log.e("AcilYardim", "EventSink.success HATA: $e")
                                }
                            }
                        }
                    }
                    val filter = IntentFilter(VolumeService.ACTION_VOLUME_EVENT)
                    LocalBroadcastManager.getInstance(this@MainActivity).registerReceiver(receiver, filter)
                    serviceReceiver = receiver

                    // VolumeService başlat
                    val serviceIntent = Intent(this@MainActivity, VolumeService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    localObserver?.let { contentResolver.unregisterContentObserver(it) }
                    localObserver = null
                    serviceReceiver?.let {
                        LocalBroadcastManager.getInstance(this@MainActivity).unregisterReceiver(it)
                    }
                    serviceReceiver = null
                    eventSink = null
                }
            })
    }

    override fun onResume() {
        super.onResume()
        requestBatteryOptimizationExemption()
        Log.d("AcilYardim", "Erişilebilirlik: ${if (VolumeAccessibilityService.isEnabled(this)) "aktif" else "devre dışı"}")
    }

    private fun requestBatteryOptimizationExemption() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
            Log.d("AcilYardim", "Pil optimizasyonu muafiyeti isteniyor")
            try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (e: Exception) {
                Log.e("AcilYardim", "Pil optimizasyonu isteği başarısız: $e")
            }
        } else {
            Log.d("AcilYardim", "Pil optimizasyonu zaten muaf")
        }
    }

    override fun onDestroy() {
        localObserver?.let { contentResolver.unregisterContentObserver(it) }
        serviceReceiver?.let {
            LocalBroadcastManager.getInstance(this).unregisterReceiver(it)
        }
        super.onDestroy()
    }
}

class VolumeContentObserver(
    handler: Handler,
    private val audioManager: AudioManager,
    private val onEvent: (String) -> Unit
) : android.database.ContentObserver(handler) {

    private val streams = listOf(
        AudioManager.STREAM_MUSIC,
        AudioManager.STREAM_RING,
        AudioManager.STREAM_NOTIFICATION,
        AudioManager.STREAM_SYSTEM,
    )

    private val lastVolumes = streams.associateWith { audioManager.getStreamVolume(it) }.toMutableMap()
    private var isResetting = false

    override fun onChange(selfChange: Boolean, uri: Uri?) {
        if (isResetting) return

        for (stream in streams) {
            val newVolume = audioManager.getStreamVolume(stream)
            val lastVolume = lastVolumes[stream] ?: continue
            val maxVolume = audioManager.getStreamMaxVolume(stream)
            val midVolume = maxVolume / 2

            if (newVolume > lastVolume && newVolume != midVolume) {
                Log.d("AcilYardim", "Volume UP - stream=$stream old=$lastVolume new=$newVolume")
                isResetting = true
                lastVolumes[stream] = midVolume
                audioManager.setStreamVolume(stream, midVolume, 0)
                isResetting = false
                onEvent("volume_up")
                return
            } else if (newVolume < lastVolume && newVolume != midVolume) {
                Log.d("AcilYardim", "Volume DOWN - stream=$stream old=$lastVolume new=$newVolume")
                isResetting = true
                lastVolumes[stream] = midVolume
                audioManager.setStreamVolume(stream, midVolume, 0)
                isResetting = false
                onEvent("volume_down")
                return
            }
        }
    }
}
