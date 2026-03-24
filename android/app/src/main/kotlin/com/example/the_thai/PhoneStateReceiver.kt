package com.example.the_thai

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat

class PhoneStateReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
        val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)

        when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                prefs.edit()
                    .putString(KEY_NUMBER, number ?: "")
                    .putString(KEY_STATE, STATE_INCOMING)
                    .remove(KEY_ACTION)
                    .apply()
                showIncomingNotification(context, number)
            }
            TelephonyManager.EXTRA_STATE_IDLE -> {
                val storedNumber = prefs.getString(KEY_NUMBER, null)
                if (storedNumber != null) {
                    prefs.edit()
                        .putString(KEY_STATE, STATE_ENDED)
                        .apply()
                    cancelNotif(context, NOTIF_INCOMING)
                    showPostCallNotification(context, storedNumber)
                }
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                cancelNotif(context, NOTIF_INCOMING)
            }
        }
    }

    private fun showIncomingNotification(context: Context, number: String?) {
        ensureChannel(context)
        val display = formatNumber(number ?: "번호 없음")

        val mainIntent = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif = NotificationCompat.Builder(context, CHANNEL_CALLS)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("수신 전화")
            .setContentText(display)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(mainIntent)
            .setVibrate(longArrayOf(0, 500, 200, 500))
            .build()

        nm(context).notify(NOTIF_INCOMING, notif)
    }

    private fun showPostCallNotification(context: Context, number: String) {
        ensureChannel(context)
        val display = formatNumber(number)

        val yesIntent = PendingIntent.getBroadcast(
            context, 1,
            Intent(context, NotificationActionReceiver::class.java)
                .putExtra(EXTRA_ACTION, ACTION_YES),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val noIntent = PendingIntent.getBroadcast(
            context, 2,
            Intent(context, NotificationActionReceiver::class.java)
                .putExtra(EXTRA_ACTION, ACTION_NO),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val bodyIntent = PendingIntent.getActivity(
            context, 3,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notif = NotificationCompat.Builder(context, CHANNEL_CALLS)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle("통화 종료 · $display")
            .setContentText("예약을 받으셨나요?")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setAutoCancel(true)
            .setContentIntent(bodyIntent)
            .setFullScreenIntent(bodyIntent, true)
            .setVibrate(longArrayOf(0, 300))
            .addAction(0, "예약 등록", yesIntent)
            .addAction(0, "아니오", noIntent)
            .build()

        nm(context).notify(NOTIF_POST_CALL, notif)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm(context).createNotificationChannel(
                NotificationChannel(
                    CHANNEL_CALLS,
                    "수신 전화",
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 500, 200, 500)
                }
            )
        }
    }

    private fun cancelNotif(context: Context, id: Int) = nm(context).cancel(id)
    private fun nm(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun formatNumber(raw: String): String {
        val d = raw.replace(Regex("[^0-9]"), "")
        return when (d.length) {
            11 -> "${d.substring(0, 3)}-${d.substring(3, 7)}-${d.substring(7)}"
            10 -> "${d.substring(0, 3)}-${d.substring(3, 6)}-${d.substring(6)}"
            else -> raw
        }
    }

    companion object {
        const val PREF_NAME = "the_thai_prefs"
        const val KEY_NUMBER = "pending_number"
        const val KEY_STATE = "pending_state"
        const val KEY_ACTION = "pending_action"
        const val STATE_INCOMING = "incoming"
        const val STATE_ENDED = "ended"
        const val ACTION_YES = "yes"
        const val ACTION_NO = "no"
        const val EXTRA_ACTION = "notif_action"
        const val CHANNEL_CALLS = "the_thai_calls"
        const val NOTIF_INCOMING = 100
        const val NOTIF_POST_CALL = 101
    }
}
