package jadwalsholat.rasyid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.NotificationManager
import android.util.Log
import android.content.SharedPreferences
import android.os.Build
import java.util.concurrent.TimeUnit

class NotificationCleanerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancelAll()
            Log.i("NotificationCleaner", "Canceled all notifications on trigger")
            // Restart the foreground service to re-create the persistent panel
            try {
                val intent = Intent(context, PrayerNotificationService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                Log.i("NotificationCleaner", "Restarted PrayerNotificationService after cleaner")
            } catch (e: Exception) {
                Log.w("NotificationCleaner", "Failed to restart service: ${e.message}")
            }
            // Try to reschedule next run based on saved preferences
            try {
                val prefs = context.getSharedPreferences("jadwalsholat_prefs", Context.MODE_PRIVATE)
                val interval = prefs.getInt("auto_clean_interval_minutes", 10)
                NotificationCleanerHelper.scheduleRepeating(context, interval.toLong())
            } catch (e: Exception) {
                Log.w("NotificationCleaner", "Failed to reschedule cleaner: ${e.message}")
            }
        } catch (e: Exception) {
            Log.w("NotificationCleaner", "Failed to cancel notifications: ${e.message}")
        }
    }
}
