package __PACKAGE__

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** ホーム画面のウィジェット：今日の残りカロリー・摂取・歩数。値はアプリを開いたときに更新される */
class MealWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context))
    }

    companion object {
        private const val PREFS = "meal_widget"

        fun save(context: Context, data: Map<String, Any?>) {
            val e = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            e.putString("date", data["date"] as? String ?: "")
            e.putInt("intake", (data["intake"] as? Number)?.toInt() ?: 0)
            e.putInt("target", (data["target"] as? Number)?.toInt() ?: 0)
            e.putInt("steps", (data["steps"] as? Number)?.toInt() ?: -1)
            e.putInt("burn", (data["burn"] as? Number)?.toInt() ?: -1)
            e.apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, MealWidgetProvider::class.java))
            for (id in ids) manager.updateAppWidget(id, views(context))
        }

        private fun views(context: Context): RemoteViews {
            val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val v = RemoteViews(context.packageName, R.layout.meal_widget)
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.JAPAN).format(Date())
            val fresh = p.getString("date", "") == today
            val intake = if (fresh) p.getInt("intake", 0) else 0
            val target = p.getInt("target", 0)
            val steps = if (fresh) p.getInt("steps", -1) else -1
            val burn = if (fresh) p.getInt("burn", -1) else -1
            val remaining = target - intake
            if (target > 0) {
                v.setTextViewText(R.id.widget_remaining, if (remaining >= 0) "あと $remaining" else "${-remaining} 超過")
                v.setTextViewText(R.id.widget_intake, "摂取 $intake / $target kcal")
                v.setProgressBar(R.id.widget_progress, target, intake.coerceAtMost(target), false)
            } else {
                v.setTextViewText(R.id.widget_remaining, "−")
                v.setTextViewText(R.id.widget_intake, "アプリを開くと表示されます")
                v.setProgressBar(R.id.widget_progress, 1, 0, false)
            }
            val extra = buildList {
                if (steps >= 0) add("歩数 ${"%,d".format(steps)}")
                if (burn > 0) add("消費 $burn kcal")
                if (!fresh) add("今日はまだ開いていません")
            }
            v.setTextViewText(R.id.widget_extra, extra.joinToString("・"))
            val open = PendingIntent.getActivity(
                context,
                0,
                context.packageManager.getLaunchIntentForPackage(context.packageName)
                    ?: Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            v.setOnClickPendingIntent(R.id.widget_root, open)
            return v
        }
    }
}
