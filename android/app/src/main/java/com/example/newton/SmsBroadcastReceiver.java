package com.example.newton;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.telephony.SmsMessage;
import android.util.Log;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import io.flutter.plugin.common.MethodChannel;

public class SmsBroadcastReceiver extends BroadcastReceiver {
    private static final String TAG = "SmsReceiver";
    private static final List<Map<String, Object>> storedMessages = new ArrayList<>();
    private MethodChannel methodChannel;
    private boolean backgroundMode = false;

    // ADD THESE METHODS
    public void setBackgroundMode(boolean backgroundMode) {
        this.backgroundMode = backgroundMode;
    }

    public void processStoredMessages(Context context) {
        List<Map<String, Object>> messagesToProcess;
        synchronized (storedMessages) {
            if (storedMessages.isEmpty()) return;
            messagesToProcess = new ArrayList<>(storedMessages);
            storedMessages.clear();
        }

        Log.d(TAG, "Processing " + messagesToProcess.size() + " stored messages");

        for (Map<String, Object> message : messagesToProcess) {
            String sender = (String) message.get("sender");
            String body = (String) message.get("body");
            long timestamp = (long) message.get("timestamp");

            if (context instanceof BackgroundService) {
                ((BackgroundService) context).handleSmsInBackground(sender, body, timestamp);
            }
        }
    }
    // END OF ADDED METHODS

    public void setMethodChannel(MethodChannel methodChannel) {
        this.methodChannel = methodChannel;
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!intent.getAction().equals("android.provider.Telephony.SMS_RECEIVED")) {
            return;
        }

        Bundle bundle = intent.getExtras();
        if (bundle == null) return;

        try {
            Object[] pdus = (Object[]) bundle.get("pdus");
            if (pdus == null) return;

            List<Map<String, Object>> messages = new ArrayList<>();
            for (Object pdu : pdus) {
                SmsMessage sms = SmsMessage.createFromPdu((byte[]) pdu);
                Map<String, Object> message = new HashMap<>();
                message.put("sender", sms.getOriginatingAddress());
                message.put("body", sms.getMessageBody());
                message.put("timestamp", sms.getTimestampMillis());
                messages.add(message);
            }

            if (backgroundMode) {
                // Background mode - store for service processing
                synchronized (storedMessages) {
                    storedMessages.addAll(messages);
                }
                Log.d(TAG, "SMS stored for background processing");
            } else {
                // In-app mode - forward to Flutter immediately
                if (methodChannel != null) {
                    methodChannel.invokeMethod("onNewSms", messages);
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "SMS processing error: " + e.getMessage());
        }
    }

    public static List<Map<String, Object>> getStoredMessages(Context context) {
        synchronized (storedMessages) {
            return new ArrayList<>(storedMessages);
        }
    }

    public static void clearStoredMessages(Context context) {
        synchronized (storedMessages) {
            storedMessages.clear();
        }
    }
}