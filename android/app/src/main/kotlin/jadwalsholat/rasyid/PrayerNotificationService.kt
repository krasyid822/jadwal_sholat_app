package jadwalsholat.rasyid

import android.app.*
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import kotlin.math.abs
import java.util.concurrent.TimeUnit

class PrayerNotificationService : Service() {
    
    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "prayer_foreground_service"
        
        fun startService(context: Context) {
            val intent = Intent(context, PrayerNotificationService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stopService(context: Context) {
            val intent = Intent(context, PrayerNotificationService::class.java)
            context.stopService(intent)
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    startForeground(NOTIFICATION_ID, createForegroundNotification())
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // If called from watchdog action, ensure service is (re)started in foreground
        if (intent?.action == "jadwalsholat.rasyid.action.WATCHDOG_RESTART") {
            // re-create foreground notification and ensure running
            startForeground(NOTIFICATION_ID, createForegroundNotification())
        }

        // Check for pending prayer times and notify if needed
        checkPrayerTimes()

        // Schedule next watchdog tick (ensure persistent restarts)
        try {
            ServiceWatchdog.scheduleWatchdog(this)
        } catch (e: Exception) {
            android.util.Log.w("PrayerService", "Failed to schedule watchdog: ${e.message}")
        }

        // Schedule WorkManager periodic restart as additional backup
        try {
            ServiceRestartWorker.schedulePeriodic(this) // uses configured/default interval
        } catch (e: Exception) {
            android.util.Log.w("PrayerService", "Failed to schedule WorkManager restart: ${e.message}")
        }

        // Return START_STICKY to request restart if killed
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // When the app task is removed (e.g., user swipes app from recent), schedule an
        // immediate one-shot WorkManager job to ensure the service is restarted.
        try {
            val work = androidx.work.OneTimeWorkRequestBuilder<ServiceRestartWorker>()
                .setInitialDelay(2, TimeUnit.SECONDS)
                .build()
            androidx.work.WorkManager.getInstance(this).enqueue(work)
        } catch (e: Exception) {
            android.util.Log.w("PrayerService", "Failed to enqueue restart worker onTaskRemoved: ${e.message}")
            // Fallback: try to directly start the foreground service
            try {
                val intent = Intent(this, PrayerNotificationService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
            } catch (ex: Exception) {
                android.util.Log.w("PrayerService", "Fallback startService failed: ${ex.message}")
            }
        }

        super.onTaskRemoved(rootIntent)
    }
    
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        try {
            ServiceWatchdog.cancelWatchdog(this)
        } catch (e: Exception) {
            android.util.Log.w("PrayerService", "Failed to cancel watchdog: ${e.message}")
        }
        try {
            // Cancel WorkManager periodic job by unique name
            androidx.work.WorkManager.getInstance(this).cancelUniqueWork("jadwalsholat_service_restart_work")
        } catch (e: Exception) {
            android.util.Log.w("PrayerService", "Failed to cancel workmanager job: ${e.message}")
        }
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Prayer Time Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps prayer time notifications running in background"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createForegroundNotification(): Notification {
        // Attach a deleteIntent so that if the notification is removed the receiver
        // can enqueue a WorkManager task to restart the service (survives process death).
        val deleteIntent = Intent(this, NotificationDeletedReceiver::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_IMMUTABLE
        }
        val deletePending = PendingIntent.getBroadcast(this, 1002, deleteIntent, flags)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Prayer Time Service")
            .setContentText("Monitoring prayer times in background")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setDeleteIntent(deletePending)
            .build()
    }
    
    private fun checkPrayerTimes() {
        // This method would check current time against prayer times
        // and trigger notifications if needed
        
        // For now, we'll use a simplified approach
        // In a real implementation, you'd get prayer times from SharedPreferences
        // and compare with current time
        
        android.util.Log.d("PrayerService", "Checking prayer times...")
    }
}
