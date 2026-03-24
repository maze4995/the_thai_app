package com.example.the_thai

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 통화 종료 알림의 [예, 예약 등록] / [아니오] 버튼 처리
 */
class NotificationActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.getStringExtra(PhoneStateReceiver.EXTRA_ACTION)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        when (action) {
            PhoneStateReceiver.ACTION_YES -> {
                // pending_action = "view_card" 저장 후 앱 실행
                context.getSharedPreferences(PhoneStateReceiver.PREF_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putString(PhoneStateReceiver.KEY_ACTION, "view_card")
                    .apply()
                nm.cancel(PhoneStateReceiver.NOTIF_POST_CALL)
                context.startActivity(
                    Intent(context, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    }
                )
            }
            PhoneStateReceiver.ACTION_NO -> {
                // 상태 초기화, 앱 실행 없이 알림만 닫기
                context.getSharedPreferences(PhoneStateReceiver.PREF_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .remove(PhoneStateReceiver.KEY_NUMBER)
                    .remove(PhoneStateReceiver.KEY_STATE)
                    .remove(PhoneStateReceiver.KEY_ACTION)
                    .apply()
                nm.cancel(PhoneStateReceiver.NOTIF_POST_CALL)
            }
        }
    }
}
