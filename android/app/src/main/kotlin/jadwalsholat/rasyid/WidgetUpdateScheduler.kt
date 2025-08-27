package jadwalsholat.rasyid

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.util.*
import java.util.concurrent.TimeUnit

object WidgetUpdateScheduler {
    private const val REQUEST_CODE = 4310

    fun scheduleDailyUpdate(context: Context, hour: Int = 0, minute: Int = 5) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, PrayerWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            }

            // Explicit mutability required on Android S+; widget update intent does not need to be mutable
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val pending = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)

            // compute next trigger at specified local time (hour:minute) today or tomorrow
            val now = Calendar.getInstance()
            val next = Calendar.getInstance()
            next.set(Calendar.HOUR_OF_DAY, hour)
            next.set(Calendar.MINUTE, minute)
            next.set(Calendar.SECOND, 0)
            next.set(Calendar.MILLISECOND, 0)

            if (!next.after(now)) {
                next.add(Calendar.DATE, 1)
            }

            val triggerAt = next.timeInMillis

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            }

            Log.d("WidgetUpdateScheduler", "Scheduled widget daily update at ${hour}:${minute} next=${Date(triggerAt)}")
        } catch (e: Exception) {
            Log.w("WidgetUpdateScheduler", "Failed to schedule widget update: ${e.message}")
        }
    }

    fun cancel(context: Context) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, PrayerWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_NO_CREATE
            }
            val pending = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
            pending?.let { alarmManager.cancel(it) }
        } catch (e: Exception) {
            Log.w("WidgetUpdateScheduler", "Failed to cancel widget update alarm: ${e.message}")
        }
    }
}
