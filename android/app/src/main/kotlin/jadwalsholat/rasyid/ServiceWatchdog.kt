package jadwalsholat.rasyid

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.concurrent.TimeUnit

object ServiceWatchdog {
    private const val REQUEST_CODE = 4201

    /**
     * Schedule an AlarmManager alarm that will send a broadcast to WatchdogReceiver.
     * Using a broadcast reduces reliance on startService flags and lets the receiver
     * explicitly start the foreground service in a way that's compatible across API levels.
     */
    fun scheduleWatchdog(context: Context, intervalMinutes: Long = 1) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, WatchdogReceiver::class.java).apply {
            action = "jadwalsholat.rasyid.action.WATCHDOG_BROADCAST"
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pending = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)

        // Allow override from SharedPreferences (key: watchdog_interval_minutes)
        val prefs = context.getSharedPreferences("jadwalsholat_prefs", Context.MODE_PRIVATE)
        val configured = prefs.getLong("watchdog_interval_minutes", intervalMinutes)
        val intervalMillis = TimeUnit.MINUTES.toMillis(configured)
        val triggerAt = System.currentTimeMillis() + intervalMillis

        // Schedule first exact run then attempt to set a repeating alarm as a fallback.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        }

        try {
            // setRepeating may be inexact on modern Android but provides a regular tick
            alarmManager.setRepeating(AlarmManager.RTC_WAKEUP, triggerAt, intervalMillis, pending)
        } catch (_: Exception) {
            // Ignore OEM restrictions; rely on exact one-shots in that case
        }
    }

    fun cancelWatchdog(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, WatchdogReceiver::class.java).apply {
            action = "jadwalsholat.rasyid.action.WATCHDOG_BROADCAST"
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_NO_CREATE
        }

        val pending = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
        pending?.let { alarmManager.cancel(it) }
    }
}
