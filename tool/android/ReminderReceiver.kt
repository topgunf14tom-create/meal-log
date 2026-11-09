package __PACKAGE__

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 記録忘れの通知。予約は Dart 側が決めた時刻だけ（記録済みの食事は予約しない）。
 * AlarmManager の非正確アラームなので数分ずれることがある。
 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "食事の記録"
        val body = intent.getStringExtra("body") ?: ""
        val id = intent.getIntExtra("id", 0)
        ensureChannel(context)
        val open = PendingIntent.getActivity(
            context,
            id,
            context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(context)
        }
        val n = builder
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try {
            nm.notify(id, n)
        } catch (_: SecurityException) {
            // 通知の許可がない
        }
    }

    companion object {
        const val CHANNEL = "meal_reminder"
        private const val MAX_IDS = 64
        private const val PREFS = "meal_reminders"

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL, "記録忘れの通知", NotificationManager.IMPORTANCE_DEFAULT)
                )
            }
        }

        private fun pending(context: Context, id: Int, title: String?, body: String?): PendingIntent {
            val i = Intent(context, ReminderReceiver::class.java).apply {
                action = "meal_log.REMINDER.$id"
                putExtra("id", id)
                if (title != null) putExtra("title", title)
                if (body != null) putExtra("body", body)
            }
            return PendingIntent.getBroadcast(
                context, id, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /** 既存の予約をすべて取り消して、[items]（id・時刻・タイトル・本文）を予約し直す */
        fun reschedule(context: Context, items: List<Map<String, Any?>>) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            for (id in 0 until MAX_IDS) am.cancel(pending(context, id, null, null))
            val now = System.currentTimeMillis()
            var count = 0
            for (m in items) {
                val id = (m["id"] as? Number)?.toInt() ?: continue
                val at = (m["at"] as? Number)?.toLong() ?: continue
                if (id !in 0 until MAX_IDS || at <= now) continue
                val p = pending(context, id, m["title"] as? String, m["body"] as? String)
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, p)
                count++
            }
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putInt("count", count).apply()
        }
    }
}
