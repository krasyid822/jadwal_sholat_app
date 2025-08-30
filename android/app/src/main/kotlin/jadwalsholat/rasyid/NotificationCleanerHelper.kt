package jadwalsholat.rasyid

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.concurrent.TimeUnit

object NotificationCleanerHelper {
    private const val REQUEST_CODE = 5210

    fun scheduleRepeating(context: Context, intervalMinutes: Long = 10) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, NotificationCleanerReceiver::class.java)

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pending = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)

        val intervalMillis = TimeUnit.MINUTES.toMillis(intervalMinutes)
        val triggerAt = System.currentTimeMillis() + intervalMillis

        // Schedule first exact run, then set a repeating alarm (inexact) for subsequent runs
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        }

        try {
            // Use setRepeating for periodic wakeups (may be inexact on newer Android versions)
            alarmManager.setRepeating(AlarmManager.RTC_WAKEUP, triggerAt, intervalMillis, pending)
        } catch (_: Exception) {
            // Some OEMs may restrict setRepeating; ignore and rely on exact one-shots
        }
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, NotificationCleanerReceiver::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_NO_CREATE
        }
        val pending = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
        pending?.let { alarmManager.cancel(it) }
    }
}
