package jadwalsholat.rasyid

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.concurrent.TimeUnit

object ServiceWatchdog {
    private const val REQUEST_CODE = 4201

    fun scheduleWatchdog(context: Context, intervalMinutes: Long = 10) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, PrayerNotificationService::class.java).apply {
            action = "jadwalsholat.rasyid.action.WATCHDOG_RESTART"
        }

        val createFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_IMMUTABLE
        }

        val pending = PendingIntent.getService(
            context,
            REQUEST_CODE,
            intent,
            createFlags
        )

    // Allow override from SharedPreferences (key: watchdog_interval_minutes)
    val prefs = context.getSharedPreferences("jadwalsholat_prefs", Context.MODE_PRIVATE)
    val configured = prefs.getLong("watchdog_interval_minutes", intervalMinutes)
    val triggerAt = System.currentTimeMillis() + TimeUnit.MINUTES.toMillis(configured)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        }
    }

    fun cancelWatchdog(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, PrayerNotificationService::class.java).apply {
            action = "jadwalsholat.rasyid.action.WATCHDOG_RESTART"
        }
        val noCreateFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        }

        val pending = PendingIntent.getService(context, REQUEST_CODE, intent, noCreateFlags)
        pending?.let { alarmManager.cancel(it) }
    }
}
