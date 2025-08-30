package jadwalsholat.rasyid

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import android.preference.PreferenceManager
import java.text.SimpleDateFormat
import java.util.*

class PrayerAppWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        updateAllWidgets(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        // When the first widget is added, schedule an update via the app's service
        updateAllWidgets(context)
    }

    private fun updateAllWidgets(context: Context) {
        val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
        val manager = AppWidgetManager.getInstance(context)
        val thisAppWidget = ComponentName(context.packageName, javaClass.name)
        val appWidgetIds = manager.getAppWidgetIds(thisAppWidget)

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_prayer_layout)

            // Read cached values with safe defaults
            val location = prefs.getString("widget_location", "Lokasi tidak tersedia") ?: "Lokasi tidak tersedia"
            val subuh = prefs.getString("widget_subuh", "--:--") ?: "--:--"
            val dzuhur = prefs.getString("widget_dzuhur", "--:--") ?: "--:--"
            val ashar = prefs.getString("widget_ashar", "--:--") ?: "--:--"
            val maghrib = prefs.getString("widget_maghrib", "--:--") ?: "--:--"
            val isya = prefs.getString("widget_isya", "--:--") ?: "--:--"
            val updatedMs = prefs.getLong("widget_last_update_ms", 0L)

            views.setTextViewText(R.id.widget_location, location)
            views.setTextViewText(R.id.widget_subuh, subuh)
            views.setTextViewText(R.id.widget_dzuhur, dzuhur)
            views.setTextViewText(R.id.widget_ashar, ashar)
            views.setTextViewText(R.id.widget_maghrib, maghrib)
            views.setTextViewText(R.id.widget_isya, isya)

            val updatedText = if (updatedMs > 0) {
                val sdf = SimpleDateFormat("HH:mm", Locale.getDefault())
                "${sdf.format(Date(updatedMs))}"
            } else {
                "-"
            }
            views.setTextViewText(R.id.widget_updated, updatedText)

            // Clicking the widget opens the app
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pi = PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            views.setOnClickPendingIntent(R.id.widget_location, pi)

            manager.updateAppWidget(widgetId, views)
        }
    }
}
