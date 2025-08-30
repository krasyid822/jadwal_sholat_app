package jadwalsholat.rasyid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

class NotificationDeletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        try {
            val work = OneTimeWorkRequestBuilder<ServiceRestartWorker>()
                .setInitialDelay(2, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context).enqueue(work)
        } catch (e: Exception) {
            android.util.Log.w("NotificationDeleted", "Failed to enqueue restart work: ${e.message}")
            // As last resort, try to directly start the service
            try {
                val svc = Intent(context, PrayerNotificationService::class.java)
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    context.startForegroundService(svc)
                } else {
                    context.startService(svc)
                }
            } catch (ex: Exception) {
                android.util.Log.w("NotificationDeleted", "Direct start failed: ${ex.message}")
            }
        }
    }
}
