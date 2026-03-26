package com.example.the_thai

import android.content.Context
import android.os.Build
import android.provider.ContactsContract
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channel = "com.example.the_thai/native_call"

    private fun getContactsByPrefix(prefix: String): List<Map<String, String>> {
        val results = mutableListOf<Map<String, String>>()
        val uri = ContactsContract.Data.CONTENT_URI
        val projection = arrayOf(
            ContactsContract.Data.RAW_CONTACT_ID,
            ContactsContract.Data.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER,
        )
        val selection =
            "${ContactsContract.Data.MIMETYPE} = ? AND " +
            "${ContactsContract.Data.DISPLAY_NAME} LIKE ?"
        val selectionArgs = arrayOf(
            ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE,
            "$prefix%",
        )
        val cursor = contentResolver.query(
            uri, projection, selection, selectionArgs,
            "${ContactsContract.Data.DISPLAY_NAME} ASC",
        ) ?: return results

        cursor.use { c ->
            val rawIdCol = c.getColumnIndexOrThrow(ContactsContract.Data.RAW_CONTACT_ID)
            val nameCol  = c.getColumnIndexOrThrow(ContactsContract.Data.DISPLAY_NAME)
            val phoneCol = c.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)
            val seen = mutableSetOf<String>()
            while (c.moveToNext()) {
                val rawId = c.getString(rawIdCol) ?: continue
                val name  = c.getString(nameCol)  ?: continue
                val phone = c.getString(phoneCol) ?: continue
                if (seen.add(rawId)) {
                    results.add(mapOf("id" to rawId, "name" to name, "phone" to phone))
                }
            }
        }
        return results
    }

    private fun updateContactName(rawId: String, newName: String) {
        val mime = ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE
        val cursor = contentResolver.query(
            ContactsContract.Data.CONTENT_URI,
            arrayOf(ContactsContract.Data._ID),
            "${ContactsContract.Data.RAW_CONTACT_ID} = ? AND ${ContactsContract.Data.MIMETYPE} = ?",
            arrayOf(rawId, mime), null,
        )
        val exists = cursor?.use { it.count > 0 } ?: false
        val ops = ArrayList<android.content.ContentProviderOperation>()
        if (exists) {
            ops.add(
                android.content.ContentProviderOperation.newUpdate(ContactsContract.Data.CONTENT_URI)
                    .withSelection(
                        "${ContactsContract.Data.RAW_CONTACT_ID} = ? AND ${ContactsContract.Data.MIMETYPE} = ?",
                        arrayOf(rawId, mime),
                    )
                    .withValue(ContactsContract.CommonDataKinds.StructuredName.GIVEN_NAME, newName)
                    .withValue(ContactsContract.CommonDataKinds.StructuredName.FAMILY_NAME, "")
                    .withValue(ContactsContract.CommonDataKinds.StructuredName.MIDDLE_NAME, "")
                    .withValue(ContactsContract.CommonDataKinds.StructuredName.PREFIX, "")
                    .withValue(ContactsContract.CommonDataKinds.StructuredName.SUFFIX, "")
                    .build()
            )
        } else {
            ops.add(
                android.content.ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValue(ContactsContract.Data.RAW_CONTACT_ID, rawId)
                    .withValue(ContactsContract.Data.MIMETYPE, mime)
                    .withValue(ContactsContract.CommonDataKinds.StructuredName.GIVEN_NAME, newName)
                    .withValue(ContactsContract.CommonDataKinds.StructuredName.FAMILY_NAME, "")
                    .build()
            )
        }
        if (ops.isNotEmpty()) contentResolver.applyBatch(ContactsContract.AUTHORITY, ops)
    }

    private fun findContactByPhone(phone: String): Map<String, String>? {
        val uri = ContactsContract.Data.CONTENT_URI
        val projection = arrayOf(
            ContactsContract.Data.RAW_CONTACT_ID,
            ContactsContract.Data.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER,
            ContactsContract.CommonDataKinds.Phone.NORMALIZED_NUMBER,
        )
        val normalized = if (phone.startsWith("0"))
            "+82${phone.substring(1)}" else phone
        val selection =
            "${ContactsContract.Data.MIMETYPE} = ? AND (" +
            "${ContactsContract.CommonDataKinds.Phone.NUMBER} = ? OR " +
            "${ContactsContract.CommonDataKinds.Phone.NORMALIZED_NUMBER} = ?)"
        val selectionArgs = arrayOf(
            ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE,
            phone,
            normalized,
        )
        val cursor = contentResolver.query(uri, projection, selection, selectionArgs, null)
            ?: return null
        cursor.use { c ->
            if (!c.moveToFirst()) return null
            val rawId = c.getString(c.getColumnIndexOrThrow(ContactsContract.Data.RAW_CONTACT_ID)) ?: return null
            val name  = c.getString(c.getColumnIndexOrThrow(ContactsContract.Data.DISPLAY_NAME)) ?: ""
            val ph    = c.getString(c.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)) ?: ""
            return mapOf("id" to rawId, "name" to name, "phone" to ph)
        }
    }

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
                    "updateContactName" -> {
                        val rawId = call.argument<String>("rawId") ?: ""
                        val name  = call.argument<String>("name")  ?: ""
                        try {
                            updateContactName(rawId, name)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("CONTACTS_ERROR", e.message, null)
                        }
                    }
                    "getContactsByPrefix" -> {
                        val prefix = call.argument<String>("prefix") ?: ""
                        try {
                            result.success(getContactsByPrefix(prefix))
                        } catch (e: Exception) {
                            result.error("CONTACTS_ERROR", e.message, null)
                        }
                    }
                    "findContactByPhone" -> {
                        val phone = call.argument<String>("phone") ?: ""
                        try {
                            result.success(findContactByPhone(phone))
                        } catch (e: Exception) {
                            result.error("CONTACTS_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
