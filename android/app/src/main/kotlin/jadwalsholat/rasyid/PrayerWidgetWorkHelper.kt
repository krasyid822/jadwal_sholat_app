package jadwalsholat.rasyid

import android.content.Context
import androidx.work.*
import java.util.concurrent.TimeUnit

object PrayerWidgetWorkHelper {
    private const val UNIQUE_PERIODIC = "jadwalsholat_widget_periodic"

    fun scheduleDaily(context: Context, intervalMinutes: Long = 60) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
            .build()

        val request = PeriodicWorkRequestBuilder<PrayerWidgetUpdateWorker>(intervalMinutes, TimeUnit.MINUTES)
            .setInitialDelay(1, TimeUnit.MINUTES)
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(UNIQUE_PERIODIC, ExistingPeriodicWorkPolicy.REPLACE, request)
    }

    fun enqueueImmediate(context: Context) {
        PrayerWidgetUpdateWorker.enqueueImmediate(context)
    }
}
