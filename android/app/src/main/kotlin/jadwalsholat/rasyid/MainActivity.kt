package jadwalsholat.rasyid

import android.os.Bundle
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        @JvmStatic
        var flutterEngineInstance: FlutterEngine? = null
    }
    private val CHANNEL = "jadwalsholat.rasyid/alarm"
    private lateinit var alarmManagerHelper: AlarmManagerHelper
    private val WEBCHANNEL = "jadwalsholat.rasyid/web"
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        alarmManagerHelper = AlarmManagerHelper(this)
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    flutterEngineInstance = flutterEngine
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setExactAlarm" -> {
                    val timeInMillis = call.argument<Long>("time") ?: 0L
                    val title = call.argument<String>("title") ?: "Prayer Time"
                    val body = call.argument<String>("body") ?: "It's time for prayer"
                    val notificationId = call.argument<Int>("notificationId") ?: 0
                    val autoPlayPrayer = call.argument<String>("autoPlayPrayer")
                    val autoPlayTick = call.argument<Boolean>("autoPlayTick") ?: false

                    alarmManagerHelper.setExactAlarm(timeInMillis, title, body, notificationId, autoPlayPrayer, autoPlayTick)
                    result.success("Alarm set successfully")
                }
                "cancelAlarm" -> {
                    val notificationId = call.argument<Int>("notificationId") ?: 0
                    alarmManagerHelper.cancelAlarm(notificationId)
                    result.success("Alarm cancelled successfully")
                }
                "startForegroundService" -> {
                    PrayerNotificationService.startService(this)
                    result.success("Foreground service started")
                }
                "stopForegroundService" -> {
                    PrayerNotificationService.stopService(this)
                    result.success("Foreground service stopped")
                }
                "scheduleNotificationCleaner" -> {
                    val minutes = call.argument<Int>("minutes") ?: 10
                    NotificationCleanerHelper.scheduleRepeating(this, minutes.toLong())
                    result.success("Cleaner scheduled")
                }
                "setWatchdogInterval" -> {
                    val minutes = call.argument<Int>("minutes") ?: 1
                    try {
                        val prefs = getSharedPreferences("jadwalsholat_prefs", Context.MODE_PRIVATE)
                        prefs.edit().putLong("watchdog_interval_minutes", minutes.toLong()).apply()
                        // Reschedule watchdog with new interval
                        ServiceWatchdog.scheduleWatchdog(this, minutes.toLong())
                        result.success("Watchdog interval set")
                    } catch (e: Exception) {
                        result.error("WATCHDOG_ERR", "Failed to set watchdog interval: ${e.message}", null)
                    }
                }
                    "persistPrayerTimes" -> {
                        try {
                            val args = call.arguments as? Map<String, String>
                            val prefs = getSharedPreferences("jadwalsholat_prefs", Context.MODE_PRIVATE)
                            val editor = prefs.edit()
                            if (args != null) {
                                for ((k, v) in args) {
                                    editor.putString(k, v)
                                }
                            }
                            editor.apply()
                            // Ensure native foreground service reads the new times immediately
                            try {
                                PrayerNotificationService.startService(this)
                            } catch (e: Exception) {
                                // best-effort; ignore failures here
                            }
                            result.success("persisted")
                        } catch (e: Exception) {
                            result.error("PERSIST_ERR", "Failed to persist prayer times: ${e.message}", null)
                        }
                    }
                "cancelNotificationCleaner" -> {
                    NotificationCleanerHelper.cancel(this)
                    result.success("Cleaner cancelled")
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Web channel - allow Flutter to open native Qibla web activity and inject locations
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WEBCHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openQiblaWeb" -> {
                    val url = call.argument<String>("url") ?: "https://qiblafinder.withgoogle.com/"
                    val intent = android.content.Intent(this, QiblaWebActivity::class.java)
                    intent.putExtra("url", url)
                    startActivity(intent)
                    result.success(true)
                }
                "injectLocation" -> {
                    // Expect a map with lat, lon, accuracy, timestamp
                    val lat = call.argument<Double>("lat")
                    val lon = call.argument<Double>("lon")
                    val accuracy = call.argument<Double>("accuracy")
                    val ts = call.argument<Long>("timestamp")

                    // If QiblaWebActivity is active, forward to it
                    try {
                        QiblaWebActivity.sendInjectedLocation(lat, lon, accuracy, ts)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ACTIVITY_ERROR", "Failed to send location to WebView: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Audio channel - play assets as ringtone/notification using Android MediaPlayer
        val AUDIO_CHANNEL = "jadwalsholat.rasyid/audio"
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playRingtone" -> {
                    // Prefer raw resource playback by resource name
                    val resName = call.argument<String>("res")
                    try {
                        if (resName != null) {
                            AndroidAudioHelper.playRawResourceAsRingtone(this, resName)
                        } else {
                            val assetPath = call.argument<String>("asset") ?: "audios/adzan.opus"
                            AndroidAudioHelper.playAssetAsRingtone(this, assetPath)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", "Failed to play ringtone: ${e.message}", null)
                    }
                }
                "stopRingtone" -> {
                    try {
                        AndroidAudioHelper.stop()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", "Failed to stop ringtone: ${e.message}", null)
                    }
                }
                "playCountdownTick" -> {
                    val resName = call.argument<String>("res") ?: "tick"
                    try {
                        AndroidAudioHelper.playRawOnce(this, resName)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", "Failed to play tick: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

    // ...existing method channels above...

            // Health channel - Flutter reports heartbeat; native can query last heartbeat
            val HEALTH_CHANNEL = "jadwalsholat.rasyid/health"
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HEALTH_CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "reportHeartbeat" -> {
                        try {
                            val prefs = getSharedPreferences("jadwalsholat_prefs", Context.MODE_PRIVATE)
                            val ts = System.currentTimeMillis()
                            prefs.edit().putLong("flutter_last_heartbeat_ms", ts).apply()
                            result.success(ts)
                        } catch (e: Exception) {
                            result.error("HEALTH_ERR", "Failed to store heartbeat: ${e.message}", null)
                        }
                    }
                    "getLastHeartbeat" -> {
                        try {
                            val prefs = getSharedPreferences("jadwalsholat_prefs", Context.MODE_PRIVATE)
                            val ts = prefs.getLong("flutter_last_heartbeat_ms", 0L)
                            result.success(ts)
                        } catch (e: Exception) {
                            result.error("HEALTH_ERR", "Failed to read heartbeat: ${e.message}", null)
                        }
                    }
                    "getBootReceivedTs" -> {
                        try {
                            val prefs = getSharedPreferences("jadwalsholat_prefs", Context.MODE_PRIVATE)
                            val ts = prefs.getLong("boot_received_ts", 0L)
                            result.success(ts)
                        } catch (e: Exception) {
                            result.error("HEALTH_ERR", "Failed to read boot ts: ${e.message}", null)
                        }
                    }
                    "isBootReceiverTriggeredSinceBoot" -> {
                        try {
                            val prefs = getSharedPreferences("jadwalsholat_prefs", Context.MODE_PRIVATE)
                            val bootTs = prefs.getLong("boot_received_ts", 0L)
                            // Compute device boot start time = now - elapsedRealtime
                            val now = System.currentTimeMillis()
                            val uptime = android.os.SystemClock.elapsedRealtime()
                            val bootStart = now - uptime
                            val triggered = bootTs >= bootStart && bootTs != 0L
                            result.success(triggered)
                        } catch (e: Exception) {
                            result.error("HEALTH_ERR", "Failed to check boot receiver: ${e.message}", null)
                        }
                    }
                    "openAppSettings" -> {
                        try {
                            val intent = android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            val uri = android.net.Uri.fromParts("package", packageName, null)
                            intent.data = uri
                            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ACTIVITY_ERR", "Failed to open app settings: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
