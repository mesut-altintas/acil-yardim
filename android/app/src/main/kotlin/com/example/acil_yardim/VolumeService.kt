package com.example.acil_yardim

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.localbroadcastmanager.content.LocalBroadcastManager

class VolumeService : Service() {

    private var observer: VolumeContentObserver? = null
    private var silentTrack: AudioTrack? = null
    @Volatile private var silentRunning = false

    override fun onCreate() {
        super.onCreate()
        Log.d("AcilYardim", "VolumeService başladı")
        startForeground(NOTIF_ID, buildNotification())
        startSilentAudio()

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val obs = VolumeContentObserver(Handler(Looper.getMainLooper()), audioManager) { event ->
            Log.d("AcilYardim", "VolumeService event: $event")
            val intent = Intent(ACTION_VOLUME_EVENT).putExtra(EXTRA_EVENT, event)
            LocalBroadcastManager.getInstance(this@VolumeService).sendBroadcast(intent)
        }
        contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, obs)
        observer = obs
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        observer?.let { contentResolver.unregisterContentObserver(it) }
        stopSilentAudio()
        Log.d("AcilYardim", "VolumeService durdu")
        super.onDestroy()
    }

    private fun startSilentAudio() {
        try {
            val sampleRate = 8000
            val minBuf = AudioTrack.getMinBufferSize(
                sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_8BIT
            )
            silentTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_8BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(minBuf)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            silentTrack?.play()
            silentRunning = true
            // Arka planda sessiz PCM yaz — müzik stream'i aktif tutar
            Thread {
                val silence = ByteArray(minBuf)
                while (silentRunning) {
                    silentTrack?.write(silence, 0, silence.size)
                }
            }.start()
            Log.d("AcilYardim", "Sessiz ses akışı başlatıldı")
        } catch (e: Exception) {
            Log.e("AcilYardim", "Sessiz ses hatası: $e")
        }
    }

    private fun stopSilentAudio() {
        silentRunning = false
        try {
            silentTrack?.stop()
            silentTrack?.release()
        } catch (_: Exception) {}
        silentTrack = null
    }

    private fun buildNotification(): Notification {
        val channelId = "acil_volume"
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(channelId, "AcilYardım", NotificationManager.IMPORTANCE_MIN)
                .apply { setShowBadge(false) }
        )
        return Notification.Builder(this, channelId)
            .setContentTitle("AcilYardım aktif")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val NOTIF_ID = 1001
        const val ACTION_VOLUME_EVENT = "com.acilyardim.VOLUME_EVENT"
        const val EXTRA_EVENT = "event"
    }
}
