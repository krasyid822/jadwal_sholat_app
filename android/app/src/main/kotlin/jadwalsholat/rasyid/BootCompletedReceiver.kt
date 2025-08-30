package jadwalsholat.rasyid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            // Record that boot completed receiver ran
            try {
                val prefs = context.getSharedPreferences("jadwalsholat_prefs", Context.MODE_PRIVATE)
                prefs.edit().putLong("boot_received_ts", System.currentTimeMillis()).apply()
            } catch (e: Exception) {
                android.util.Log.w("BootReceiver", "Failed to record boot timestamp: ${e.message}")
            }
            // Schedule initial watchdog after boot
            try {
                ServiceWatchdog.scheduleWatchdog(context)
            } catch (e: Exception) {
                android.util.Log.w("BootReceiver", "Failed to schedule watchdog on boot: ${e.message}")
            }
            // Widget support removed; nothing to schedule here.
        }
    }
}
