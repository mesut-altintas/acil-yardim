package com.example.acil_yardim

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.media.AudioManager
import android.net.Uri
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings

class VolumeService : Service() {

    private var volumeObserver: VolumeContentObserver? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIF_ID, buildNotification())
        registerVolumeObserver()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(p0: Intent?): IBinder? = null

    override fun onDestroy() {
        volumeObserver?.let { contentResolver.unregisterContentObserver(it) }
        super.onDestroy()
    }

    private fun registerVolumeObserver() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val observer = VolumeContentObserver(
            Handler(Looper.getMainLooper()),
            audioManager
        ) { event ->
            // Broadcast ile MainActivity'e ilet
            sendBroadcast(Intent(ACTION_VOLUME_EVENT).putExtra(EXTRA_EVENT, event))
        }
        contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, observer)
        volumeObserver = observer
    }

    private fun buildNotification(): Notification {
        val channelId = "volume_service"
        val channel = NotificationChannel(
            channelId,
            "AcilYardım Tetikleme",
            NotificationManager.IMPORTANCE_LOW
        ).apply { setShowBadge(false) }

        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(channel)

        return Notification.Builder(this, channelId)
            .setContentTitle("AcilYardım Aktif")
            .setContentText("AB Shutter dinleniyor...")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .build()
    }

    companion object {
        const val NOTIF_ID = 1001
        const val ACTION_VOLUME_EVENT = "com.acilyardim.VOLUME_EVENT"
        const val EXTRA_EVENT = "event"
    }
}

class VolumeContentObserver(
    handler: Handler,
    private val audioManager: AudioManager,
    private val onEvent: (String) -> Unit
) : ContentObserver(handler) {

    private var lastVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
    private val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)

    override fun onChange(selfChange: Boolean, uri: Uri?) {
        val newVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        if (newVolume > lastVolume) {
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxVolume / 2, 0)
            lastVolume = maxVolume / 2
            onEvent("volume_up")
        } else if (newVolume < lastVolume) {
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxVolume / 2, 0)
            lastVolume = maxVolume / 2
            onEvent("volume_down")
        }
    }
}
