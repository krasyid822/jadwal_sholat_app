package jadwalsholat.rasyid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * BroadcastReceiver for watchdog alarms. Tries to start the foreground service
 * immediately and schedules a WorkManager one-shot retry (unique) with backoff
 * so that devices which prevent immediate service start still get a robust retry.
 */
class WatchdogReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        Log.d("WatchdogReceiver", "Received watchdog broadcast, attempting to start service")

        val svcIntent = Intent(context, PrayerNotificationService::class.java).apply {
            action = "jadwalsholat.rasyid.action.WATCHDOG_RESTART"
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(svcIntent)
            } else {
                context.startService(svcIntent)
            }
            Log.d("WatchdogReceiver", "Requested startForegroundService/startService")
        } catch (t: Throwable) {
            Log.w("WatchdogReceiver", "Immediate start failed: ${t.message}", t)
        }

        // Regardless of immediate start outcome, schedule a WorkManager one-shot retry
        // to probe and (if needed) start the service. This increases reliability
        // on OEMs that block immediate starts.
        try {
            val work = OneTimeWorkRequestBuilder<ServiceRestartWorker>()
                .setInitialDelay(10, TimeUnit.SECONDS)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                "jadwalsholat_watchdog_retry",
                ExistingWorkPolicy.REPLACE,
                work
            )
            Log.d("WatchdogReceiver", "Enqueued watchdog retry WorkManager job")
        } catch (we: Throwable) {
            Log.w("WatchdogReceiver", "Failed to enqueue watchdog retry work: ${we.message}", we)
        }
    }
}
