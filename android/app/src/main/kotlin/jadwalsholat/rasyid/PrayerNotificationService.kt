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
    // Use same ID as Flutter enhanced foreground service to keep them in sync
    private const val NOTIFICATION_ID = 4000
    // Channel id must match Flutter's _foregroundWidgetChannelId
    private const val CHANNEL_ID = "foreground_widget_channel"
        
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
                "Panel Jadwal Sholat (Latar Depan)",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Panel notifikasi persistent yang menampilkan nama lokasi dan 5 waktu sholat"
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

        // Build an inbox style notification from SharedPreferences
        val prefs = getSharedPreferences("jadwalsholat_prefs", Context.MODE_PRIVATE)
        val place = prefs.getString("last_place_name", "") ?: ""

        val prayerKeys = listOf("subuh", "dzuhur", "ashar", "maghrib", "isya")
        val inboxStyle = NotificationCompat.InboxStyle()

        fun emojiFor(key: String): String {
            return when (key) {
                "subuh" -> "🕯️"
                "dzuhur" -> "🌞"
                "ashar" -> "🌤️"
                "maghrib" -> "🌇"
                "isya" -> "🌙"
                else -> "•"
            }
        }

        for (key in prayerKeys) {
            val stored = prefs.getString("prayer_time_$key", "") ?: ""
            val display = if (stored.length >= 16) {
                try {
                    stored.substring(11, 16)
                } catch (e: Exception) {
                    stored
                }
            } else if (stored.isNotEmpty()) {
                stored
            } else {
                "--:--"
            }
            val displayName = key.replaceFirstChar { it.uppercaseChar() }
            val emoji = emojiFor(key)
            inboxStyle.addLine("$emoji  $displayName  $display")
        }

        val contentTitle = if (place.isNotEmpty()) place else "Panel Jadwal Sholat"

        // If user enabled auto-expand, use a higher priority to increase
        // the likelihood the system shows the expanded inbox style immediately.
        val autoExpand = prefs.getBoolean("foreground_widget_auto_expand", false)
        val priority = if (autoExpand) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_LOW

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(contentTitle)
            .setStyle(inboxStyle)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setShowWhen(false)
            .setPriority(priority)
            .setDeleteIntent(deletePending)

        // Try to set a large icon and accent color from application icon in a
        // safe way (handle bitmap, vector and adaptive icons).
        try {
            val appIconDrawable = try {
                packageManager.getApplicationIcon(packageName)
            } catch (e: Exception) {
                null
            }

            if (appIconDrawable != null) {
                val width = if (appIconDrawable.intrinsicWidth > 0) appIconDrawable.intrinsicWidth else 128
                val height = if (appIconDrawable.intrinsicHeight > 0) appIconDrawable.intrinsicHeight else 128
                val bmp = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888)
                val canvas = android.graphics.Canvas(bmp)
                appIconDrawable.setBounds(0, 0, canvas.width, canvas.height)
                appIconDrawable.draw(canvas)
                builder.setLargeIcon(bmp)
                builder.color = android.graphics.Color.parseColor("#4DB6AC")
            }
        } catch (e: Exception) {
            // Ignore issues converting drawable to bitmap; fallback to no large icon
        }

        return builder.build()
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
