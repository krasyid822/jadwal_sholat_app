package jadwalsholat.rasyid

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat

class AlarmManagerHelper(private val context: Context) {
    
    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    
    fun setExactAlarm(timeInMillis: Long, title: String, body: String, notificationId: Int, autoPlayPrayer: String?, autoPlayTick: Boolean) {
        try {
            val intent = Intent(context, NotificationReceiver::class.java).apply {
                action = "jadwalsholat.rasyid.PRAYER_ALARM"
                putExtra("title", title)
                putExtra("body", body)
                putExtra("notification_id", notificationId)
                if (!autoPlayPrayer.isNullOrEmpty()) putExtra("autoPlayPrayer", autoPlayPrayer)
                if (autoPlayTick) putExtra("autoPlayTick", true)
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                notificationId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // Check if we can schedule exact alarms
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (alarmManager.canScheduleExactAlarms()) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        timeInMillis,
                        pendingIntent
                    )
                    Log.d("AlarmManagerHelper", "Exact alarm set for: $timeInMillis")
                } else {
                    // Fallback to inexact alarm
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        timeInMillis,
                        pendingIntent
                    )
                    Log.d("AlarmManagerHelper", "Inexact alarm set for: $timeInMillis (exact not permitted)")
                }
            } else {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    timeInMillis,
                    pendingIntent
                )
                Log.d("AlarmManagerHelper", "Legacy exact alarm set for: $timeInMillis")
            }
        } catch (e: Exception) {
            Log.e("AlarmManagerHelper", "Failed to set alarm", e)
        }
    }
    
    fun cancelAlarm(notificationId: Int) {
        try {
            val intent = Intent(context, NotificationReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                notificationId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            alarmManager.cancel(pendingIntent)
            Log.d("AlarmManagerHelper", "Alarm cancelled for ID: $notificationId")
        } catch (e: Exception) {
            Log.e("AlarmManagerHelper", "Failed to cancel alarm", e)
        }
    }
}
