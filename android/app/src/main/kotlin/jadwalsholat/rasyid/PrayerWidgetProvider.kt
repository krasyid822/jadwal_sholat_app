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
        // ensure daily scheduling exists
        try {
            WidgetUpdateScheduler.scheduleDailyUpdate(context)
        } catch (e: Exception) {
            Log.w("PrayerWidget", "Failed to schedule daily widget update: ${e.message}")
        }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        // Called when the first widget is added: ensure we schedule daily updates
        try {
            WidgetUpdateScheduler.scheduleDailyUpdate(context)
            Log.i("PrayerWidget", "onEnabled: scheduled daily widget updates")
        } catch (e: Exception) {
            Log.w("PrayerWidget", "onEnabled failed to schedule updates: ${e.message}")
        }
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        // Called when the last widget is removed: cancel scheduled updates
        try {
            WidgetUpdateScheduler.cancel(context)
            Log.i("PrayerWidget", "onDisabled: canceled widget updates")
        } catch (e: Exception) {
            Log.w("PrayerWidget", "onDisabled failed to cancel updates: ${e.message}")
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            val mgr = AppWidgetManager.getInstance(context)
            updateAllWidgets(context, mgr)
            // re-schedule after manual refresh
            try {
                WidgetUpdateScheduler.scheduleDailyUpdate(context)
            } catch (e: Exception) {
                Log.w("PrayerWidget", "Failed to schedule daily widget update on receive: ${e.message}")
            }
        }
    }

    private fun updateAllWidgets(context: Context, appWidgetManager: AppWidgetManager) {
        val compName = ComponentName(context, PrayerWidgetProvider::class.java)
        val ids = appWidgetManager.getAppWidgetIds(compName)
    Log.i("PrayerWidget", "updateAllWidgets called for package=${context.packageName}, widgetIds=${ids.contentToString()}")
    for (id in ids) {
            try {
        // Choose layout by widget options (min width) to support 1x3 compact widget
                val opts = appWidgetManager.getAppWidgetOptions(id)
                val minW = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
                val minH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
                // Log reported options to help tuning on different launchers
                Log.i("PrayerWidget", "Widget id=$id options: minWidth=$minW minHeight=$minH opts=$opts")
                // If min width is large enough, pick the 1x3 layout. Use a permissive threshold to support more launchers
                val layoutId = if (minW >= 200) R.layout.widget_prayer_1x3 else R.layout.widget_prayer
        val views = RemoteViews(context.packageName, layoutId)
        val isOneByThree = layoutId == R.layout.widget_prayer_1x3

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
            var foundPrefsFile: String? = null

        for (file in candidatePrefFiles) {
                try {
                    val p = context.getSharedPreferences(file, Context.MODE_PRIVATE)
                    val all = p.all
            Log.i("PrayerWidget", "Inspecting prefs file=$file, entries=${all.keys}")

                    // If we haven't found place yet, try variants
                    if (place == null) {
                        for (k in keyVariants[0]) {
                            val v = sanitize(all[k])
                            if (v != null) {
                                place = v
                                foundPrefsFile = file
                                break
                            }
                        }
                    }

                    if (nextPrayer == null) {
                        for (k in keyVariants[1]) {
                            val v = sanitize(all[k])
                            if (v != null) {
                                nextPrayer = v
                                if (foundPrefsFile == null) foundPrefsFile = file
                                break
                            }
                        }
                    }

                    if (nextPrayerTime == null) {
                        for (k in keyVariants[2]) {
                            val v = sanitize(all[k])
                            if (v != null) {
                                nextPrayerTime = v
                                if (foundPrefsFile == null) foundPrefsFile = file
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

            // If explicit next prayer keys are missing, try to derive from prayer_time_* keys
            var displayPrayerName = finalNextPrayer
            var displayPrayerTime = finalNextPrayerTime

            if ((displayPrayerName == "-" || displayPrayerTime == "-") ) {
                try {
                    // Look into FlutterSharedPreferences for keys like flutter.prayer_time_subuh or prayer_time_subuh
                    val p = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val all = p.all
                    val now = Date()
                    val candidates = mutableListOf<Pair<String,String>>() // (prayerName, isoTime)

                    for ((k,v) in all) {
                        val key = k.toString()
                        if (key.contains("prayer_time_")) {
                            val prayer = key.substringAfterLast("prayer_time_")
                            val value = sanitize(v)
                            if (value != null) {
                                candidates.add(Pair(prayer, value))
                            }
                        }
                    }

                    // Parse ISO or simple time string and find next upcoming
                    var bestPrayer: String? = null
                    var bestTimeStr: String? = null
                    var bestTime: Date? = null

                    val isoFormats = listOf("yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss'Z'")
                    val timeOnly = SimpleDateFormat("HH:mm", Locale.getDefault())

                    for (c in candidates) {
                        val raw = c.second
                        var parsed: Date? = null
                        // Try ISO first using SimpleDateFormat (avoid javax.xml.bind which isn't on Android)
                        try {
                            val iso1 = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault())
                            iso1.timeZone = TimeZone.getDefault()
                            parsed = iso1.parse(raw)
                        } catch (_: Exception) {
                        }
                        if (parsed == null) {
                            try {
                                val isoZ = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.getDefault())
                                isoZ.timeZone = TimeZone.getTimeZone("UTC")
                                parsed = isoZ.parse(raw)
                            } catch (_: Exception) {
                            }
                        }
                        if (parsed == null) {
                            // Try time-only HH:mm and assume today
                            try {
                                val t = timeOnly.parse(raw)
                                val cal = Calendar.getInstance()
                                val tc = Calendar.getInstance()
                                tc.time = t
                                cal.set(Calendar.HOUR_OF_DAY, tc.get(Calendar.HOUR_OF_DAY))
                                cal.set(Calendar.MINUTE, tc.get(Calendar.MINUTE))
                                cal.set(Calendar.SECOND, 0)
                                parsed = cal.time
                            } catch (_: Exception) {
                            }
                        }

                        if (parsed != null) {
                            // If parsed time is earlier than now, consider it as tomorrow's occurrence
                            val parsedCal = Calendar.getInstance()
                            parsedCal.time = parsed
                            val candidateCal = Calendar.getInstance()
                            candidateCal.time = parsed
                            // set candidate to today with parsed time
                            val tc = Calendar.getInstance()
                            tc.time = parsed
                            val candidate = Calendar.getInstance()
                            candidate.set(Calendar.HOUR_OF_DAY, tc.get(Calendar.HOUR_OF_DAY))
                            candidate.set(Calendar.MINUTE, tc.get(Calendar.MINUTE))
                            candidate.set(Calendar.SECOND, 0)
                            // If candidate is not after now, roll to tomorrow
                            if (!candidate.time.after(now)) {
                                candidate.add(Calendar.DATE, 1)
                            }
                            val candidateDate = candidate.time

                            if (bestTime == null) {
                                bestTime = candidateDate
                                bestPrayer = c.first
                                bestTimeStr = raw
                            } else if (candidateDate.before(bestTime)) {
                                bestTime = candidateDate
                                bestPrayer = c.first
                                bestTimeStr = raw
                            }
                        }
                    }

                    if (bestPrayer != null && bestTimeStr != null) {
                        displayPrayerName = bestPrayer.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString() }
                        // format time-only nicely
                        try {
                            // Try parse bestTimeStr as ISO (UTC or local)
                            var parsedDate: Date? = null
                            try {
                                val iso1 = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault())
                                iso1.timeZone = TimeZone.getDefault()
                                parsedDate = iso1.parse(bestTimeStr)
                            } catch (_: Exception) {}
                            if (parsedDate == null) {
                                try {
                                    val isoZ = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.getDefault())
                                    isoZ.timeZone = TimeZone.getTimeZone("UTC")
                                    parsedDate = isoZ.parse(bestTimeStr)
                                } catch (_: Exception) {}
                            }
                            if (parsedDate != null) {
                                displayPrayerTime = SimpleDateFormat("HH:mm", Locale.getDefault()).format(parsedDate)
                            } else {
                                // fallback keep raw or try HH:mm
                                try {
                                    val t = timeOnly.parse(bestTimeStr)
                                    if (t != null) {
                                        displayPrayerTime = timeOnly.format(t)
                                    } else {
                                        displayPrayerTime = bestTimeStr
                                    }
                                } catch (_: Exception) {
                                    displayPrayerTime = bestTimeStr
                                }
                            }
                        } catch (_: Exception) {
                            displayPrayerTime = bestTimeStr
                        }
                    }
                } catch (e: Exception) {
                    Log.w("PrayerWidget", "Failed to derive prayer_time_*: ${e.message}")
                }
                // If still no resolved next time, fallback to first available explicit prayer_time_* formatted value
                if ((displayPrayerName == "-" || displayPrayerTime == "-") ) {
                    try {
                        val p = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        fun readKeySimple(k: String): String? {
                            val v = p.getString(k, null) ?: p.getString("flutter.$k", null)
                            if (v == null) return null
                            val s = v.trim()
                            if (s.isEmpty() || s.equals("null", ignoreCase = true)) return null
                            return s
                        }
                        // Attempt to use prayer_times_cache_* if present (some app versions store a JSON cache)
                        val all = p.all
                        for ((k,v) in all) {
                            try {
                                if (k.toString().startsWith("flutter.prayer_times_cache") || k.toString().startsWith("prayer_times_cache")) {
                                    val rawCache = v?.toString() ?: continue
                                    Log.i("PrayerWidget", "Found prayer_times_cache key=$k, attempting JSON parse")
                                    try {
                                        val obj = org.json.JSONObject(rawCache)
                                        // expect keys like subuh, dzuhur, ashar, maghrib, isya with ISO/time strings
                                        val order2 = listOf("subuh","dzuhur","ashar","maghrib","isya")
                                        for (kk in order2) {
                                            if (obj.has(kk)) {
                                                val raw = obj.optString(kk, null)
                                                if (raw != null && raw.isNotBlank()) {
                                                    displayPrayerName = kk.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString() }
                                                    // simple format attempt
                                                    displayPrayerTime = try {
                                                        val sdf = SimpleDateFormat("HH:mm", Locale.getDefault())
                                                        val parsed = sdf.parse(raw)
                                                        if (parsed != null) sdf.format(parsed) else raw
                                                    } catch (_: Exception) { raw }
                                                    Log.i("PrayerWidget", "Using cache value for $kk -> $displayPrayerTime")
                                                    break
                                                }
                                            }
                                        }
                                        if (displayPrayerTime != "-") break
                                    } catch (je: Exception) {
                                        Log.w("PrayerWidget", "prayer_times_cache JSON parse failed: ${je.message}")
                                    }
                                }
                            } catch (_: Exception) {}
                        }
                        val order = listOf("prayer_time_subuh", "prayer_time_dzuhur", "prayer_time_ashar", "prayer_time_magrib", "prayer_time_isya")
                        for (k in order) {
                            val raw = readKeySimple(k)
                            if (raw != null) {
                                // attempt to format simply by extracting HH:mm if available
                                val t = try {
                                    val sdf = SimpleDateFormat("HH:mm", Locale.getDefault())
                                    val parsed = sdf.parse(raw)
                                    if (parsed != null) sdf.format(parsed) else raw
                                } catch (_: Exception) { raw }
                                displayPrayerTime = t
                                displayPrayerName = k.substringAfterLast("_").replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString() }
                                break
                            }
                        }
                    } catch (e: Exception) {
                        Log.w("PrayerWidget", "Fallback read prayer_time_* failed: ${e.message}")
                    }
                }
            }

            // Populate RemoteViews with resolved values
            Log.i("PrayerWidget", "Resolved place=$finalPlace nextPrayer=$displayPrayerName nextTime=$displayPrayerTime layout=${if (isOneByThree) "1x3" else "default"}")
            try {
                views.setTextViewText(R.id.widget_place, finalPlace)
            } catch (e: Exception) {
                Log.w("PrayerWidget", "Failed to set widget_place text: ${Log.getStackTraceString(e)}")
            }

            // For compact 1x3 layout, show main countdown and two prayer rows (Subuh and Dzuhur)
            if (isOneByThree) {
                try {
                    // Use the big countdown area to show next prayer time
                    views.setTextViewText(R.id.widget_countdown, displayPrayerTime)
                } catch (e: Exception) {
                    Log.w("PrayerWidget", "Failed to set widget_countdown: ${Log.getStackTraceString(e)}")
                }
            }

            // Try to read explicit prayer_time_* keys and populate rows
            try {
                val p = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                fun readKey(k: String): String? {
                    val v = p.getString(k, null) ?: p.getString("flutter.$k", null)
                    if (v == null) return null
                    val s = v.trim()
                    if (s.isEmpty() || s.equals("null", ignoreCase = true)) return null
                    return s
                }

                val subuh = readKey("prayer_time_subuh")
                val dzuhur = readKey("prayer_time_dzuhur")
                val ashar = readKey("prayer_time_ashar")
                val maghrib = readKey("prayer_time_maghrib")
                val isya = readKey("prayer_time_isya")

                // Robust formatter: accepts HH:mm, ISO with optional milliseconds, and ISO Z
                fun formatTime(raw: String?): String {
                    if (raw == null) return "-"
                    val s = raw.trim()
                    if (s.isEmpty() || s.equals("null", ignoreCase = true)) return "-"

                    // Helper to try multiple date patterns
                    fun tryParse(pattern: String, value: String, tz: TimeZone? = null): Date? {
                        return try {
                            val sdf = SimpleDateFormat(pattern, Locale.getDefault())
                            if (tz != null) sdf.timeZone = tz
                            sdf.parse(value)
                        } catch (_: Exception) {
                            null
                        }
                    }

                    // Common ISO variants we expect from Flutter (with or without milliseconds)
                    val isoCandidates = listOf(
                        Pair("yyyy-MM-dd'T'HH:mm:ss.SSS", null),
                        Pair("yyyy-MM-dd'T'HH:mm:ss", null),
                        Pair("yyyy-MM-dd'T'HH:mm:ss'Z'", TimeZone.getTimeZone("UTC"))
                    )

                    // Try parsing as HH:mm first
                    try {
                        val t = tryParse("HH:mm", s, null)
                        if (t != null) return SimpleDateFormat("HH:mm", Locale.getDefault()).format(t)
                    } catch (_: Exception) {}

                    // Try ISO variants
                    for (c in isoCandidates) {
                        val d = tryParse(c.first, s, c.second)
                        if (d != null) return SimpleDateFormat("HH:mm", Locale.getDefault()).format(d)
                    }

                    // Some inputs include fractional seconds with more precision (e.g. .000)
                    if (s.contains('.')) {
                        val beforeDot = s.substringBefore('.')
                        // attempt to re-append seconds if missing
                        val tryVals = listOf(beforeDot, s)
                        for (v in tryVals) {
                            for (c in isoCandidates) {
                                val d = tryParse(c.first, v, c.second)
                                if (d != null) return SimpleDateFormat("HH:mm", Locale.getDefault()).format(d)
                            }
                        }
                    }

                    // Fallback: return raw trimmed but shortened if it's long
                    return if (s.length > 5 && s.contains("T")) {
                        // try to extract time portion
                        val timePart = s.substringAfter('T').substringBefore('.')
                        if (timePart.length >= 5) timePart.substring(0,5) else s
                    } else s
                }

                // Only set the views that exist in the chosen layout
                try { views.setTextViewText(R.id.widget_subuh_time, formatTime(subuh)) } catch (e: Exception) { Log.w("PrayerWidget", "widget_subuh_time set failed: ${Log.getStackTraceString(e)}") }
                try { views.setTextViewText(R.id.widget_zuhur_time, formatTime(dzuhur)) } catch (e: Exception) { Log.w("PrayerWidget", "widget_zuhur_time set failed: ${Log.getStackTraceString(e)}") }
                if (!isOneByThree) {
                    try { views.setTextViewText(R.id.widget_ashar_time, formatTime(ashar)) } catch (e: Exception) { Log.w("PrayerWidget", "widget_ashar_time set failed: ${Log.getStackTraceString(e)}") }
                    try { views.setTextViewText(R.id.widget_magrib_time, formatTime(maghrib)) } catch (e: Exception) { Log.w("PrayerWidget", "widget_magrib_time set failed: ${Log.getStackTraceString(e)}") }
                    try { views.setTextViewText(R.id.widget_isya_time, formatTime(isya)) } catch (e: Exception) { Log.w("PrayerWidget", "widget_isya_time set failed: ${Log.getStackTraceString(e)}") }
                }
            } catch (e: Exception) {
                Log.w("PrayerWidget", "Failed to populate prayer rows: ${Log.getStackTraceString(e)}")
            }

            // Add a refresh pending intent (tap the widget to refresh)
            val refreshIntent = Intent(context, PrayerWidgetProvider::class.java).apply { action = ACTION_REFRESH }
            val pending = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.getBroadcast(context, 0, refreshIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
            } else {
                PendingIntent.getBroadcast(context, 0, refreshIntent, PendingIntent.FLAG_UPDATE_CURRENT)
            }
            try {
                views.setOnClickPendingIntent(R.id.widget_root, pending)
            } catch (e: Exception) {
                Log.w("PrayerWidget", "Failed to set OnClickPendingIntent: ${Log.getStackTraceString(e)}")
            }
                // Log a concise snapshot of the preferences used for this widget to help debug missing values
                try {
                    if (foundPrefsFile != null) {
                        val dbgPref = context.getSharedPreferences(foundPrefsFile, Context.MODE_PRIVATE)
                        val dbgAll = dbgPref.all
                        val keysSummary = dbgAll.keys.joinToString(",")
                        Log.i("PrayerWidget", "Using prefs file=$foundPrefsFile keys=[$keysSummary]")
                    }
                } catch (e: Exception) {
                    Log.w("PrayerWidget", "Failed to log debug prefs: ${Log.getStackTraceString(e)}")
                }

                appWidgetManager.updateAppWidget(id, views)
                Log.i("PrayerWidget", "Updated widget id=$id for package=${context.packageName}")
            } catch (e: Exception) {
                // If anything goes wrong while preparing the full layout, apply a minimal
                // fallback layout so the widget host doesn't show a loading error card.
                Log.e("PrayerWidget", "Failed to update widget id=$id: ${Log.getStackTraceString(e)}")
                try {
                    val safe = RemoteViews(context.packageName, R.layout.widget_prayer_fallback)
                    appWidgetManager.updateAppWidget(id, safe)
                    Log.i("PrayerWidget", "Applied fallback widget layout for id=$id")
                } catch (ex: Exception) {
                    Log.e("PrayerWidget", "Failed to apply fallback for widget id=$id: ${Log.getStackTraceString(ex)}")
                }
            }
        }
    }
}
