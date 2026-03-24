package com.example.the_thai

import android.content.Context
import android.os.Build
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channel = "com.example.the_thai/native_call"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences(PhoneStateReceiver.PREF_NAME, Context.MODE_PRIVATE)

                when (call.method) {
                    "getPendingCall" -> {
                        val number = prefs.getString(PhoneStateReceiver.KEY_NUMBER, null)
                        val state  = prefs.getString(PhoneStateReceiver.KEY_STATE, null)
                        val action = prefs.getString(PhoneStateReceiver.KEY_ACTION, null)
                        if (number != null && state != null) {
                            result.success(
                                mapOf("number" to number, "state" to state, "action" to (action ?: ""))
                            )
                        } else {
                            result.success(null)
                        }
                    }
                    "clearPendingCall" -> {
                        prefs.edit()
                            .remove(PhoneStateReceiver.KEY_NUMBER)
                            .remove(PhoneStateReceiver.KEY_STATE)
                            .remove(PhoneStateReceiver.KEY_ACTION)
                            .apply()
                        result.success(null)
                    }
                    "sendSms" -> {
                        val phone = call.argument<String>("phone")
                        val message = call.argument<String>("message")
                        if (phone == null || message == null) {
                            result.error("INVALID_ARG", "phone or message is null", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                getSystemService(SmsManager::class.java)
                            } else {
                                @Suppress("DEPRECATION")
                                SmsManager.getDefault()
                            }
                            val parts = smsManager.divideMessage(message)
                            if (parts.size == 1) {
                                smsManager.sendTextMessage(phone, null, message, null, null)
                            } else {
                                smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SMS_ERROR", e.message, null)
                        }
                    }
                    "getSmsTemplate" -> {
                        result.success(prefs.getString("sms_template", null))
                    }
                    "setSmsTemplate" -> {
                        val template = call.argument<String>("template") ?: ""
                        prefs.edit().putString("sms_template", template).apply()
                        result.success(null)
                    }
                    "getSmsDepletionTemplate" -> {
                        result.success(prefs.getString("sms_depletion_template", null))
                    }
                    "setSmsDepletionTemplate" -> {
                        val template = call.argument<String>("template") ?: ""
                        prefs.edit().putString("sms_depletion_template", template).apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
