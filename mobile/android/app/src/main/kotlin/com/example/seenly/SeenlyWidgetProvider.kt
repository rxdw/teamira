package com.example.seenly

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Renders whatever [com.example.seenly's Flutter side — see
 * lib/services/home_widget_service.dart] last pushed via
 * `HomeWidget.saveWidgetData`: a countdown to the next co-viewing
 * evening, today's pick, the current streak, or an empty/locked
 * placeholder. android:name in AndroidManifest.xml
 * (".SeenlyWidgetProvider") and the `androidName` the Dart side passes
 * to `HomeWidget.updateWidget` both have to keep matching this class
 * name — nothing enforces that at compile time on either side.
 *
 * One layout ([R.layout.seenly_widget]) serves every state; this just
 * decides which of its two "leading" views (the poster vs. the big
 * number) is visible and fills in the three text fields. Colors here
 * are the same fixed hex [seenly_widget_background] already commits to
 * — see that drawable's own doc comment for why this doesn't try to
 * track the in-app skin/flavor/brightness choice.
 */
class SeenlyWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val state = widgetData.getString("state", "empty") ?: "empty"
        val title = widgetData.getString("title", "") ?: ""
        val subtitle = widgetData.getString("subtitle", "") ?: ""
        val number = widgetData.getString("number", "") ?: ""
        val posterPath = widgetData.getString("poster_path", "") ?: ""

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.seenly_widget)
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_subtitle, subtitle)

            // "pick" gets the poster in the leading slot, "countdown"/
            // "streak" get the big number there instead, "empty"/
            // "locked" get neither — title/subtitle alone, left-aligned
            // in the space the leading slot would have used.
            val poster = if (state == "pick" && posterPath.isNotEmpty()) decodeRounded(posterPath) else null
            if (poster != null) {
                views.setImageViewBitmap(R.id.widget_poster, poster)
                views.setViewVisibility(R.id.widget_poster, android.view.View.VISIBLE)
                views.setViewVisibility(R.id.widget_number, android.view.View.GONE)
            } else if (number.isNotEmpty()) {
                views.setTextViewText(R.id.widget_number, number)
                views.setViewVisibility(R.id.widget_number, android.view.View.VISIBLE)
                views.setViewVisibility(R.id.widget_poster, android.view.View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_number, android.view.View.GONE)
                views.setViewVisibility(R.id.widget_poster, android.view.View.GONE)
            }

            // Tapping anywhere on the widget just opens the app — no
            // deep link routing into a specific screen yet (see
            // HomeWidgetService's own doc comment on scope), so every
            // state uses the same plain launch intent.
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                val pendingIntent = PendingIntent.getActivity(context, widgetId, launchIntent, flags)
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /**
     * Loads the PNG [HomeWidgetService._renderPoster] already rendered
     * (see that method — it's pre-fetched and pre-sized by Flutter, this
     * only rounds the corners) and draws it onto a same-size canvas
     * clipped to a rounded rect. RemoteViews ImageViews have no outline-
     * clip of their own below API 31, so this is done once here instead
     * of relying on the platform.
     */
    private fun decodeRounded(path: String): Bitmap? {
        val file = File(path)
        if (!file.exists()) return null
        val source = BitmapFactory.decodeFile(path) ?: return null

        val output = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val rect = Rect(0, 0, source.width, source.height)
        val rectF = RectF(rect)
        val radius = source.width * 0.18f

        canvas.drawRoundRect(rectF, radius, radius, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(source, rect, rect, paint)
        return output
    }
}
