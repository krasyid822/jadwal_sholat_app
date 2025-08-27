package jadwalsholat.rasyid

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.*

class PrayerWidgetProvider : AppWidgetProvider() {
    companion object {
        const val ACTION_REFRESH = "jadwalsholat.rasyid.ACTION_REFRESH_WIDGET"
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        updateAllWidgets(context, appWidgetManager)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            val mgr = AppWidgetManager.getInstance(context)
            updateAllWidgets(context, mgr)
        }
    }

    private fun updateAllWidgets(context: Context, appWidgetManager: AppWidgetManager) {
        val compName = ComponentName(context, PrayerWidgetProvider::class.java)
        val ids = appWidgetManager.getAppWidgetIds(compName)
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.widget_prayer)

            // Load last known location and next prayer time from SharedPreferences (saved by Flutter code)
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            // Try multiple possible keys because the Flutter plugin may store keys with or without the
            // "flutter." prefix depending on plugin/platform behaviour or older app versions.
            fun readStringVar(varNames: List<String>, default: String): String {
                for (k in varNames) {
                    try {
                        val v = prefs.getString(k, null)
                        if (v != null) {
                            val trimmed = v.trim()
                            if (trimmed.isNotEmpty() && trimmed.lowercase(Locale.getDefault()) != "null") return trimmed
                        }
                    } catch (_: Exception) {
                        // ignore and try next
                    }
                }
                return default
            }

            val place = readStringVar(listOf("flutter.last_place_name", "last_place_name"), "Lokasi tidak diketahui")
            val nextPrayer = readStringVar(listOf("flutter.next_prayer_name", "next_prayer_name"), "-")
            val nextPrayerTime = readStringVar(listOf("flutter.next_prayer_time", "next_prayer_time"), "-")

            views.setTextViewText(R.id.widget_place, place)
            views.setTextViewText(R.id.widget_prayer_name, nextPrayer)
            views.setTextViewText(R.id.widget_prayer_time, nextPrayerTime)

            // Add a refresh pending intent (tap the widget to refresh)
            val refreshIntent = Intent(context, PrayerWidgetProvider::class.java).apply { action = ACTION_REFRESH }
            val pending = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.getBroadcast(context, 0, refreshIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
            } else {
                PendingIntent.getBroadcast(context, 0, refreshIntent, PendingIntent.FLAG_UPDATE_CURRENT)
            }
            views.setOnClickPendingIntent(R.id.widget_root, pending)

            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
