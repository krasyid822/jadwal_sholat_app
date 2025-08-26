package jadwalsholat.rasyid

import android.content.Context
import android.content.Intent
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit
import androidx.work.Constraints
import androidx.work.NetworkType
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.BackoffPolicy

class ServiceRestartWorker(appContext: Context, params: WorkerParameters): CoroutineWorker(appContext, params) {
    companion object {
        private const val UNIQUE_WORK_NAME = "jadwalsholat_service_restart_work"

        fun schedulePeriodic(context: Context, intervalMinutes: Long = 30) {
            val prefs = context.getSharedPreferences("jadwalsholat_prefs", Context.MODE_PRIVATE)
            val configuredInterval = prefs.getLong("workmanager_interval_minutes", intervalMinutes)
            val requireBatteryNotLow = prefs.getBoolean("workmanager_require_battery_not_low", false)

            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
                .setRequiresBatteryNotLow(requireBatteryNotLow)
                .build()

            val request = PeriodicWorkRequestBuilder<ServiceRestartWorker>(configuredInterval, TimeUnit.MINUTES)
                .setInitialDelay(configuredInterval, TimeUnit.MINUTES)
                .setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 60, TimeUnit.SECONDS)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_WORK_NAME,
                ExistingPeriodicWorkPolicy.REPLACE,
                request
            )
        }
    }

    override suspend fun doWork(): Result {
        try {
            // Try a direct probe into the Flutter engine first
            val directOk = HealthProbeHelper.probeFlutterDirect(applicationContext, 5)
            if (directOk) {
                // Flutter responded to direct probe, healthy
                return Result.success()
            }

            // Fallback: Check last heartbeat reported by Flutter
            val lastHeartbeat = HealthProbeHelper.getLastHeartbeatMs(applicationContext)
            val now = System.currentTimeMillis()
            // Stale threshold default 5 minutes, overridable via prefs key 'stale_threshold_minutes'
            val prefs = applicationContext.getSharedPreferences("jadwalsholat_prefs", Context.MODE_PRIVATE)
            val configuredStale = prefs.getLong("stale_threshold_minutes", 5L)
            val staleThreshold = TimeUnit.MINUTES.toMillis(configuredStale)

            if (lastHeartbeat != 0L && now - lastHeartbeat < staleThreshold) {
                // Flutter is healthy according to last heartbeat
                return Result.success()
            }

            // Ensure the native foreground service is running to host Flutter background tasks
            val intent = Intent(applicationContext, PrayerNotificationService::class.java)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(intent)
            } else {
                applicationContext.startService(intent)
            }

            return Result.success()
        } catch (e: Exception) {
            android.util.Log.w("ServiceRestartWorker", "Failed to start service: ${e.message}")
            return Result.retry()
        }
    }
}
