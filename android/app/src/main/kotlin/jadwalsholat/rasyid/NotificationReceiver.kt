package jadwalsholat.rasyid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class NotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("NotificationReceiver", "Received alarm broadcast")
        
        // Extract notification data from intent
        val title = intent.getStringExtra("title") ?: "Prayer Time"
        val body = intent.getStringExtra("body") ?: "It's time for prayer"
        val notificationId = intent.getIntExtra("notification_id", System.currentTimeMillis().toInt())
        
        // Create pending intent for Stop action
        val stopIntent = Intent(context, StopAudioReceiver::class.java).apply {
            action = "jadwalsholat.rasyid.action.STOP_AUDIO"
        }
        val stopPending = PendingIntent.getBroadcast(
            context,
            notificationId + 1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Create notification with Stop action
        val builder = NotificationCompat.Builder(context, "prayer_channel")
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .addAction(android.R.drawable.ic_media_pause, "Stop", stopPending)

        // If this will auto-play audio, make notification ongoing so user sees Stop
        val autoPlayPrayer = intent.getStringExtra("autoPlayPrayer")
        val autoPlayTick = intent.getBooleanExtra("autoPlayTick", false)
        if (!autoPlayPrayer.isNullOrEmpty() || autoPlayTick) {
            builder.setOngoing(true)
        }

        val notification = builder.build()
            
        // Show notification
        with(NotificationManagerCompat.from(context)) {
            try {
                notify(notificationId, notification)
                Log.d("NotificationReceiver", "Notification shown: $title")
                // If this alarm includes autoPlayPrayer extra, start native playback
                if (!autoPlayPrayer.isNullOrEmpty()) {
                    try {
                        AndroidAudioHelper.stop()
                        val resName = if (autoPlayPrayer.lowercase() == "subuh") "adzan_subuh" else "adzan"
                        AndroidAudioHelper.playRawResourceAsRingtone(context, resName)
                        Log.d("NotificationReceiver", "Started auto-play adzan for: $autoPlayPrayer")
                    } catch (e: Exception) {
                        Log.e("NotificationReceiver", "Failed to auto-play adzan: ${e.message}")
                    }
                }

                // If autoPlayTick flag, play tick once (non-looping)
                if (autoPlayTick) {
                    try {
                        AndroidAudioHelper.playRawOnce(context, "tick")
                        Log.d("NotificationReceiver", "Played countdown tick")
                    } catch (e: Exception) {
                        Log.e("NotificationReceiver", "Failed to play tick: ${e.message}")
                    }
                }
            } catch (e: SecurityException) {
                Log.e("NotificationReceiver", "Security exception showing notification", e)
            }
        }
    }
}
