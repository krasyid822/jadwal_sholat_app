package jadwalsholat.rasyid

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
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
            // Candidate SharedPreferences file names to inspect
            val candidatePrefFiles = listOf("FlutterSharedPreferences", "${context.packageName}_preferences")

            // Keys to look for (both flutter-prefixed and unprefixed)
            val keyVariants = listOf(
                listOf("flutter.last_place_name", "last_place_name"),
                listOf("flutter.next_prayer_name", "next_prayer_name"),
                listOf("flutter.next_prayer_time", "next_prayer_time")
            )

            // Helper to extract a string value from a SharedPreferences map, sanitizing empty/null-like values
            fun sanitize(v: Any?): String? {
                if (v == null) return null
                val s = v.toString().trim()
                if (s.isEmpty()) return null
                if (s.equals("null", ignoreCase = true)) return null
                return s
            }

            var place: String? = null
            var nextPrayer: String? = null
            var nextPrayerTime: String? = null

            for (file in candidatePrefFiles) {
                try {
                    val p = context.getSharedPreferences(file, Context.MODE_PRIVATE)
                    val all = p.all
                    Log.d("PrayerWidget", "Inspecting prefs file=$file, entries=${all.keys}")

                    // If we haven't found place yet, try variants
                    if (place == null) {
                        for (k in keyVariants[0]) {
                            val v = sanitize(all[k])
                            if (v != null) {
                                place = v
                                break
                            }
                        }
                    }

                    if (nextPrayer == null) {
                        for (k in keyVariants[1]) {
                            val v = sanitize(all[k])
                            if (v != null) {
                                nextPrayer = v
                                break
                            }
                        }
                    }

                    if (nextPrayerTime == null) {
                        for (k in keyVariants[2]) {
                            val v = sanitize(all[k])
                            if (v != null) {
                                nextPrayerTime = v
                                break
                            }
                        }
                    }

                    // If all found, stop searching
                    if (place != null && nextPrayer != null && nextPrayerTime != null) break
                } catch (e: Exception) {
                    Log.w("PrayerWidget", "Error reading prefs file=$file: ${e.message}")
                }
            }

            // Final fallbacks
            val finalPlace = place ?: "Lokasi tidak diketahui"
            val finalNextPrayer = nextPrayer ?: "-"
            val finalNextPrayerTime = nextPrayerTime ?: "-"

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
