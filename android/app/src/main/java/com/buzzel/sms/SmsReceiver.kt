package com.buzzel.sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.ContactsContract
import android.provider.Telephony
import android.util.Log

class SmsReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsReceiver"
        var listener: SmsListener? = null
    }

    interface SmsListener {
        fun onSmsReceived(sender: String, contactName: String?, body: String)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        // Group message parts by sender
        val grouped = mutableMapOf<String, StringBuilder>()
        for (msg in messages) {
            val sender = msg.originatingAddress ?: continue
            grouped.getOrPut(sender) { StringBuilder() }.append(msg.messageBody ?: "")
        }

        for ((sender, bodyBuilder) in grouped) {
            val body = bodyBuilder.toString()
            val contactName = resolveContactName(context, sender)
            Log.d(TAG, "SMS from $sender ($contactName): $body")
            listener?.onSmsReceived(sender, contactName, body)
        }
    }

    private fun resolveContactName(context: Context, phoneNumber: String): String? {
        return try {
            val uri = android.net.Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                android.net.Uri.encode(phoneNumber)
            )
            context.contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        cursor.getString(cursor.getColumnIndexOrThrow(ContactsContract.PhoneLookup.DISPLAY_NAME))
                    } else null
                }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to resolve contact name", e)
            null
        }
    }
}
