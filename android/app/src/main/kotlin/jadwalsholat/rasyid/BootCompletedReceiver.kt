package jadwalsholat.rasyid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            // Schedule initial watchdog after boot
            try {
                ServiceWatchdog.scheduleWatchdog(context)
            } catch (e: Exception) {
                android.util.Log.w("BootReceiver", "Failed to schedule watchdog on boot: ${e.message}")
            }
            // Ensure widget daily update alarm is scheduled after boot
            try {
                WidgetUpdateScheduler.scheduleDailyUpdate(context)
            } catch (e: Exception) {
                android.util.Log.w("BootReceiver", "Failed to schedule widget update on boot: ${e.message}")
            }
        }
    }
}
