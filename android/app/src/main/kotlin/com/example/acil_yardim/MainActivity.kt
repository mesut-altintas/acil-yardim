package com.example.acil_yardim

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {

    private var eventSink: EventChannel.EventSink? = null
    private var volumeReceiver: BroadcastReceiver? = null

    override fun onResume() {
        super.onResume()
        requestBatteryOptimizationExemption()
    }

    private fun requestBatteryOptimizationExemption() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.acilyardim/volume_button")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events

                    // Foreground Service başlat
                    val serviceIntent = Intent(this@MainActivity, VolumeService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }

                    // Broadcast receiver kaydet
                    val receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context, intent: Intent) {
                            val event = intent.getStringExtra(VolumeService.EXTRA_EVENT)
                            if (event != null) {
                                runOnUiThread { eventSink?.success(event) }
                            }
                        }
                    }
                    val filter = IntentFilter(VolumeService.ACTION_VOLUME_EVENT)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(receiver, filter, RECEIVER_NOT_EXPORTED)
                    } else {
                        registerReceiver(receiver, filter)
                    }
                    volumeReceiver = receiver
                }

                override fun onCancel(arguments: Any?) {
                    volumeReceiver?.let { unregisterReceiver(it) }
                    volumeReceiver = null
                    eventSink = null
                    stopService(Intent(this@MainActivity, VolumeService::class.java))
                }
            })
    }

    override fun onDestroy() {
        volumeReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
        }
        super.onDestroy()
    }
}
