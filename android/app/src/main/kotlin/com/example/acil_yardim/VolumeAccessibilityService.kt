package com.example.acil_yardim

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import androidx.localbroadcastmanager.content.LocalBroadcastManager

class VolumeAccessibilityService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) return false

        val eventName = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> "volume_up"
            KeyEvent.KEYCODE_VOLUME_DOWN -> "volume_down"
            else -> return false
        }

        Log.d("AcilYardim", "AccessibilityService key: $eventName")

        val intent = Intent(VolumeService.ACTION_VOLUME_EVENT)
            .putExtra(VolumeService.EXTRA_EVENT, eventName)
        LocalBroadcastManager.getInstance(this).sendBroadcast(intent)

        return false // sesi değiştirmeye izin ver (true yaparsak engeller)
    }

    companion object {
        fun isEnabled(context: android.content.Context): Boolean {
            val enabledServices = android.provider.Settings.Secure.getString(
                context.contentResolver,
                android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            val pkg = context.packageName
            // Sistem iki formatı da kullanabilir: pkg/.Class veya pkg/pkg.Class
            return enabledServices.split(':').any { entry ->
                entry.startsWith(pkg, ignoreCase = true) &&
                entry.contains("VolumeAccessibilityService", ignoreCase = true)
            }
        }
    }
}
