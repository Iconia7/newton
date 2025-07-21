package com.example.newton;

import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.preference.PreferenceManager;
import android.provider.Telephony;
import android.telephony.SmsManager;
import android.telephony.SubscriptionInfo;
import android.telephony.SubscriptionManager;
import android.telephony.TelephonyManager;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class MainActivity extends FlutterActivity {
    private static final String TAG = "MainActivity";
    private static final String SMS_EVENT_CHANNEL = "com.example.newton/smsEvent";
    private static final String USSD_CHANNEL = "com.example.newton/ussd";
    private static final String SIM_CHANNEL = "com.example.newton/sim";
    private static final String SMS_SENDER_CHANNEL = "com.example.newton/sms_sender";
    private static final String SERVICE_CONTROL_CHANNEL = "com.example.newton/service_control";
    private static final String BACKGROUND_SERVICE_CHANNEL = "com.example.newton/background_service";


    // Default template messages
    private static final String DEFAULT_SUCCESS_TEMPLATE = "Thank you [first_name] for choosing and entrusting Nexora Bingwa Sokoni and purchasing [offer] for [amount]. Have a nice time.";
    private static final String DEFAULT_FAILURE_TEMPLATE = "Dear [first_name], there was a delay while processing your purchase of [offer] for [amount]. Please wait a little bit for it to be loaded.";
    private static final String DEFAULT_NO_OFFER_TEMPLATE = "Sorry [first_name], the amount [amount] sent does not match any of our offers.\nWhatsapp 0115332870 to get list of our offers.";
    private static final String DEFAULT_ALREADY_TEMPLATE = "Hey [first_name], Your number [phone] has already been recommended bingwa bundles today\nReply with\n1. Recommend tomorrow\n2. Recommend to this \"number\" (new)";

    // Method channels
    private MethodChannel ussdMethodChannel;
    private MethodChannel simMethodChannel;
    private MethodChannel smsSenderMethodChannel;
    private MethodChannel serviceControlMethodChannel;
    private MethodChannel backgroundServiceMethodChannel;
    
    // Event channel
    private EventChannel smsEventChannel;
    private SmsStreamHandler smsStreamHandler;
    
    // Broadcast receiver for in-app SMS handling
    private SmsBroadcastReceiver smsBroadcastReceiver;
    
    // Keyword lists for USSD response checking
    private List<String> successKeywords = new ArrayList<>();
    private List<String> failureKeywords = new ArrayList<>();
    private SharedPreferences sharedPreferences;
    
    // Current transaction being processed
    private Map<String, Object> _currentAutoBuyMpesaTransaction = null;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        // Initialize SharedPreferences
        sharedPreferences = PreferenceManager.getDefaultSharedPreferences(this);
        
        // Start background service
        startSmsBackgroundService();
        
        // SMS Event Channel for real-time SMS in app
        smsEventChannel = new EventChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SMS_EVENT_CHANNEL);
        smsStreamHandler = new SmsStreamHandler(this);
        smsEventChannel.setStreamHandler(smsStreamHandler);
        
        // USSD Method Channel
        ussdMethodChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), USSD_CHANNEL);
        ussdMethodChannel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("triggerUssd")) {
                String ussdCode = call.argument("ussdCode");
                Integer simSubscriptionId = call.argument("simSubscriptionId");
                Map<String, Object> transaction = call.argument("transaction");
                
                if (ussdCode != null && simSubscriptionId != null) {
                    _currentAutoBuyMpesaTransaction = transaction;
                    triggerUssdCode(ussdCode, simSubscriptionId, result);
                } else {
                    result.error("INVALID_ARGUMENTS", "USSD code or SIM ID is missing", null);
                }
            } else {
                result.notImplemented();
            }
        });
        
        // SIM Method Channel
        simMethodChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SIM_CHANNEL);
        simMethodChannel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("getSimCards")) {
                result.success(getAvailableSimCards());
            } else {
                result.notImplemented();
            }
        });
        
        // SMS Sender Method Channel
        smsSenderMethodChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SMS_SENDER_CHANNEL);
        smsSenderMethodChannel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("sendSms")) {
                String recipientAddress = call.argument("recipientAddress");
                String messageBody = call.argument("messageBody");
                if (recipientAddress != null && messageBody != null) {
                    sendSms(recipientAddress, messageBody);
                    result.success(true);
                } else {
                    result.error("INVALID_ARGUMENTS", "Recipient address or message body is null", null);
                }
            } else if (call.method.equals("getStoredMessages")) {
                List<Map<String, Object>> storedMessages = SmsBroadcastReceiver.getStoredMessages(this);
                result.success(storedMessages);
                SmsBroadcastReceiver.clearStoredMessages(this);
            } else {
                result.notImplemented();
            }
        });
        
        // Service Control Method Channel
        serviceControlMethodChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SERVICE_CONTROL_CHANNEL);
        serviceControlMethodChannel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("updateKeywords")) {
                Map<String, List<String>> keywords = (Map<String, List<String>>) call.arguments;
                successKeywords = keywords.get("successKeywords");
                failureKeywords = keywords.get("failureKeywords");
                
                // Update the background service with new keywords
                updateServiceKeywords();
                result.success(true);
            } else if (call.method.equals("startService")) {
                startSmsBackgroundService();
                result.success("Background service started");
            } else if (call.method.equals("stopService")) {
                stopSmsBackgroundService();
                result.success("Background service stopped");
            } else {
                result.notImplemented();
            }
        });
        
        // Background Service Method Channel
        backgroundServiceMethodChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), BACKGROUND_SERVICE_CHANNEL);
        backgroundServiceMethodChannel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "startService":
                    startSmsBackgroundService();
                    result.success("Service started");
                    break;
                    
                case "stopService":
                    stopSmsBackgroundService();
                    result.success("Service stopped");
                    break;
                    
                case "isServiceRunning":
                    boolean isRunning = isSmsBackgroundServiceRunning();
                    result.success(isRunning);
                    break;
                    
                case "handleBackgroundSms":
                    // Handle background SMS processing from service
                    Map<String, Object> smsData = (Map<String, Object>) call.arguments;
                    handleBackgroundSmsFromService(smsData);
                    result.success("SMS handled successfully");
                    break;
                    
                case "getAppStatus":
                    // Return app status information to service
                    Map<String, Object> status = new HashMap<>();
                    status.put("isActive", true);
                    status.put("timestamp", System.currentTimeMillis());
                    status.put("successKeywords", successKeywords);
                    status.put("failureKeywords", failureKeywords);
                    result.success(status);
                    break;
                    
                case "updateKeywords":
                    Map<String, List<String>> keywordUpdate = (Map<String, List<String>>) call.arguments;
                    successKeywords = keywordUpdate.get("successKeywords");
                    failureKeywords = keywordUpdate.get("failureKeywords");
                    updateServiceKeywords();
                    result.success("Keywords updated");
                    break;
                    
                default:
                    result.notImplemented();
                    break;
            }
        });
        
        // Register the SMS BroadcastReceiver for in-app use (different from background service)
        smsBroadcastReceiver = new SmsBroadcastReceiver();
        smsBroadcastReceiver.setMethodChannel(smsSenderMethodChannel);
        IntentFilter filter = new IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            registerReceiver(smsBroadcastReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(smsBroadcastReceiver, filter);
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        // Automatically start background service when app starts
        startSmsBackgroundService();
    }

    /**
     * Formats a name to have proper capitalization (first letter uppercase, rest lowercase)
     */
    private String formatName(String name) {
        if (name == null || name.isEmpty()) {
            return name;
        }
        
        String[] words = name.trim().split("\\s+");
        StringBuilder formatted = new StringBuilder();
        
        for (int i = 0; i < words.length; i++) {
            String word = words[i];
            if (!word.isEmpty()) {
                // Capitalize first character, lowercase the rest
                String formattedWord = word.substring(0, 1).toUpperCase() + 
                                     word.substring(1).toLowerCase();
                formatted.append(formattedWord);
                
                // Add space between words (except for the last word)
                if (i < words.length - 1) {
                    formatted.append(" ");
                }
            }
        }
        
        return formatted.toString();
    }

    // Background Service Management Methods
    private void startSmsBackgroundService() {
        BackgroundService.startBackgroundService(this, successKeywords, failureKeywords);
    }

    private void stopSmsBackgroundService() {
        BackgroundService.stopBackgroundService(this);
    }

    private boolean isSmsBackgroundServiceRunning() {
        // Check if service is running - you can implement this check if needed
        return true; // Placeholder
    }

    private void updateServiceKeywords() {
        // Send keywords update to background service
        Intent updateIntent = new Intent(this, BackgroundService.class);
        updateIntent.setAction("UPDATE_KEYWORDS");
        updateIntent.putStringArrayListExtra("successKeywords", new ArrayList<>(successKeywords));
        updateIntent.putStringArrayListExtra("failureKeywords", new ArrayList<>(failureKeywords));
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(updateIntent);
        } else {
            startService(updateIntent);
        }
        
        Log.d(TAG, "Keywords updated in background service");
    }

    private void handleBackgroundSmsFromService(Map<String, Object> smsData) {
        Log.d(TAG, "Handling background SMS from service: " + smsData);
        
        // Process the SMS data received from the background service
        try {
            String sender = (String) smsData.get("sender");
            String body = (String) smsData.get("body");
            Long timestamp = (Long) smsData.get("timestamp");
            
            // Process SMS based on your business logic
            // Check for M-Pesa messages, keywords, etc.
            
            Log.i(TAG, "Background SMS processed - Sender: " + sender + ", Body: " + body);
            
        } catch (Exception e) {
            Log.e(TAG, "Error handling background SMS: " + e.getMessage());
        }
    }

    private void triggerUssdCode(String ussdCode, Integer simSubscriptionId, MethodChannel.Result result) {
        Log.d(TAG, "Triggering USSD: " + ussdCode + ", SIM ID: " + simSubscriptionId);
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.CALL_PHONE) != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "CALL_PHONE permission required", null);
            return;
        }
        
        TelephonyManager baseManager = (TelephonyManager) getSystemService(Context.TELEPHONY_SERVICE);
        TelephonyManager simTelephonyManager = baseManager.createForSubscriptionId(simSubscriptionId);
        if (simTelephonyManager == null) {
            result.error("TELEPHONY_MANAGER_NULL", "No TelephonyManager for SIM ID", null);
            return;
        }
        
        sendUssdRequestAtOnce(simTelephonyManager, ussdCode, result);
    }

   // Updated sendUssdRequestAtOnce method in MainActivity.java
private void sendUssdRequestAtOnce(TelephonyManager tm, String ussdCode, MethodChannel.Result result) {
    tm.sendUssdRequest(
        ussdCode,
        new TelephonyManager.UssdResponseCallback() {
            @Override
            public void onReceiveUssdResponse(TelephonyManager tm, String request, CharSequence response) {
                new Handler(Looper.getMainLooper()).post(() -> {
                    String responseStr = response.toString().toLowerCase();
                    boolean isSuccess = checkKeywords(responseStr, successKeywords);
                    boolean isFailure = checkKeywords(responseStr, failureKeywords);
                    boolean isAlready = responseStr.contains("already");
                    
                    // Log keywords for debugging
                    Log.d(TAG, "Success keywords: " + successKeywords);
                    Log.d(TAG, "Failure keywords: " + failureKeywords);
                    Log.d(TAG, "Response: " + responseStr);
                    Log.d(TAG, "isSuccess: " + isSuccess + ", isFailure: " + isFailure);
                    
                    // Send SMS based on USSD result
                    if (isAlready) {
                        sendDirectSms("USSD_ALREADY", responseStr);
                    }
                    else if (isSuccess) {
                        sendDirectSms("USSD_SUCCESS", responseStr);
                    } else if (isFailure) {
                        sendDirectSms("USSD_FAILURE", responseStr);
                    }
                    
                    // Prepare response for Flutter
                    Map<String, Object> responseMap = new HashMap<>();
                    responseMap.put("response", responseStr);
                    responseMap.put("isSuccess", isSuccess);
                    responseMap.put("isFailure", isFailure);
                    responseMap.put("isAlready", isAlready);
                    
                    // Send response back to Flutter - this triggers token deduction
                    ussdMethodChannel.invokeMethod("onUssdResponse", responseMap);
                    
                    // Clear current transaction
                    _currentAutoBuyMpesaTransaction = null;
                });
            }
            
            @Override
            public void onReceiveUssdResponseFailed(TelephonyManager tm, String request, int failureCode) {
                new Handler(Looper.getMainLooper()).post(() -> {
                    String error = "USSD failed (code " + failureCode + ")";
                    Log.e(TAG, error);
                    
                    // Send failure SMS if we have transaction details
                    sendDirectSms("USSD_ERROR", error);
                    
                    // Prepare error response for Flutter
                    Map<String, Object> errorMap = new HashMap<>();
                    errorMap.put("error", error);
                    errorMap.put("isFailure", true);
                    errorMap.put("response", error);
                    
                    // Send error back to Flutter - no token deduction
                    ussdMethodChannel.invokeMethod("onUssdError", errorMap);
                    
                    // Clear current transaction
                    _currentAutoBuyMpesaTransaction = null;
                });
            }
        },
        new Handler(Looper.getMainLooper())
    );
    result.success("USSD sent in background");
}

// Enhanced sendDirectSms method with better logging
private void sendDirectSms(String type, String ussdResponse) {
    try {
        // Get phone number from current transaction
        String phoneNumber = null;
        if (_currentAutoBuyMpesaTransaction != null) {
            phoneNumber = (String) _currentAutoBuyMpesaTransaction.get("extractedPhoneNumber");
        }
        
        if (phoneNumber == null || phoneNumber.isEmpty()) {
            Log.w(TAG, "No phone number available for direct SMS");
            return;
        }
        
        String message = getTemplateMessage(type);
        message = replacePlaceholders(message, _currentAutoBuyMpesaTransaction);
        
        // Send SMS
        sendSms(phoneNumber, message);
        Log.i(TAG, "Direct SMS sent to " + phoneNumber + " (Type: " + type + "): " + message);
        
        // Log transaction completion
        if ("USSD_SUCCESS".equals(type)) {
            Log.i(TAG, "✅ USSD SUCCESS - SMS sent, Flutter will deduct token");
        } else if ("USSD_FAILURE".equals(type) || "USSD_ERROR".equals(type)) {
            Log.i(TAG, "❌ USSD FAILED - SMS sent, no token deduction");
        }
        
    } catch (Exception e) {
        Log.e(TAG, "Failed to send direct SMS: " + e.getMessage());
    }
}

     // Updated method to load templates from SharedPreferences
    private String getTemplateMessage(String type) {
        String message;
        switch (type) {
            case "USSD_SUCCESS":
                message = sharedPreferences.getString("sms_success", DEFAULT_SUCCESS_TEMPLATE);
                break;
            case "USSD_FAILURE":
            case "USSD_ERROR":
                message = sharedPreferences.getString("sms_failure", DEFAULT_FAILURE_TEMPLATE);
                break;
            case "USSD_ALREADY":
                message = sharedPreferences.getString("sms_already", DEFAULT_ALREADY_TEMPLATE);
                break;
            case "NO_OFFER":
                message = sharedPreferences.getString("sms_no_offer", DEFAULT_NO_OFFER_TEMPLATE);
                break;    
            default:
                message = "USSD operation completed: Unknown type";
        }
        return message;
    }
    
    private String replacePlaceholders(String message, Map<String, Object> transaction) {
        // Name splitting logic with proper formatting
        String name = (String) transaction.get("extractedName");
        if (name != null) {
            // Format the full name first
            String formattedName = formatName(name);
            String[] nameParts = formattedName.trim().split("\\s+");
            
            String firstName = nameParts.length > 0 ? nameParts[0] : "";
            String lastName = nameParts.length > 1 ? nameParts[nameParts.length - 1] : "";
            String secondName = nameParts.length > 2 ? nameParts[1] : "";

            message = message.replace("[first_name]", firstName);
            message = message.replace("[second_name]", secondName);
            message = message.replace("[last_name]", lastName);
            message = message.replace("[name]", formattedName);
        }
        
        // Amount
        if (message.contains("[amount]")) {
            Object amountObj = transaction.get("extractedAmount");
            if (amountObj != null) {
                String amount = amountObj.toString();
                if (amountObj instanceof Double) {
                    amount = String.format("Ksh %.2f", (Double) amountObj);
                }
                message = message.replace("[amount]", amount);
            }
        }
        
        // Phone
        if (message.contains("[phone]")) {
            String phone = (String) transaction.get("extractedPhoneNumber");
            if (phone != null) {
                message = message.replace("[phone]", phone);
            }
        }
        
        // Offer (plan name)
        if (message.contains("[offer]")) {
            String offer = (String) transaction.get("purchasedOffer");
            if (offer != null) {
                message = message.replace("[offer]", offer);
            }
        }
        
        return message;
    }

    private void sendSms(String recipient, String message) {
        try {
            SmsManager smsManager = SmsManager.getDefault();
            smsManager.sendTextMessage(recipient, null, message, null, null);
            Log.d(TAG, "SMS sent to " + recipient + ": " + message);
        } catch (Exception e) {
            Log.e(TAG, "Failed to send SMS: " + e.getMessage());
        }
    }

    private List<Map<String, Object>> getAvailableSimCards() {
        List<Map<String, Object>> simList = new ArrayList<>();
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
            SubscriptionManager sm = (SubscriptionManager) getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE);
            if (sm != null) {
                List<SubscriptionInfo> infos = sm.getActiveSubscriptionInfoList();
                if (infos != null) {
                    for (SubscriptionInfo info : infos) {
                        Map<String, Object> sim = new HashMap<>();
                        sim.put("subscriptionId", info.getSubscriptionId());
                        sim.put("displayName", info.getDisplayName().toString());
                        sim.put("simSlotIndex", info.getSimSlotIndex());
                        simList.add(sim);
                    }
                }
            }
        } else {
            Log.w(TAG, "READ_PHONE_STATE not granted");
        }
        return simList;
    }

    private boolean checkKeywords(String response, List<String> keywords) {
        if (response == null || keywords == null) return false;
        response = response.toLowerCase();
        for (String keyword : keywords) {
            if (keyword != null && !keyword.isEmpty() && 
                response.contains(keyword.toLowerCase())) {
                return true;
            }
        }
        return false;
    }

    @Override
    public void cleanUpFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        // Clean up all method channels
        if (ussdMethodChannel != null) ussdMethodChannel.setMethodCallHandler(null);
        if (simMethodChannel != null) simMethodChannel.setMethodCallHandler(null);
        if (smsSenderMethodChannel != null) smsSenderMethodChannel.setMethodCallHandler(null);
        if (serviceControlMethodChannel != null) serviceControlMethodChannel.setMethodCallHandler(null);
        if (backgroundServiceMethodChannel != null) backgroundServiceMethodChannel.setMethodCallHandler(null);
        
        // Clean up event channel
        if (smsEventChannel != null) {
            smsEventChannel.setStreamHandler(null);
            smsStreamHandler = null;
        }
        
        // Disconnect receiver from Flutter but don't unregister - background service handles it
        if (smsBroadcastReceiver != null) {
            smsBroadcastReceiver.setMethodChannel(null);
            try {
                unregisterReceiver(smsBroadcastReceiver);
            } catch (IllegalArgumentException e) {
                Log.w(TAG, "Receiver was not registered: " + e.getMessage());
            }
        }
        
        // Note: Don't stop background service here - let it continue running
        super.cleanUpFlutterEngine(flutterEngine);
    }

    @Override
    protected void onDestroy() {
        // Only stop service when activity is truly destroyed
        Log.d(TAG, "MainActivity onDestroy called");
        // Note: Don't stop the background service here if you want it to continue running
        // when the app is closed. Only stop it when explicitly requested.
        super.onDestroy();
    }

    private static class SmsStreamHandler implements EventChannel.StreamHandler {
        private final Context appContext;
        private android.content.BroadcastReceiver receiver;
        private EventChannel.EventSink eventSink;

        SmsStreamHandler(Context context) {
            appContext = context.getApplicationContext();
        }

        @Override
        public void onListen(Object args, EventChannel.EventSink sink) {
            this.eventSink = sink;
            receiver = new android.content.BroadcastReceiver() {
                @Override
                public void onReceive(Context context, Intent intent) {
                    if (Telephony.Sms.Intents.SMS_RECEIVED_ACTION.equals(intent.getAction())) {
                        android.telephony.SmsMessage[] msgs = Telephony.Sms.Intents.getMessagesFromIntent(intent);
                        for (android.telephony.SmsMessage msg : msgs) {
                            Map<String, Object> sms = new HashMap<>();
                            sms.put("sender", msg.getDisplayOriginatingAddress());
                            sms.put("body", msg.getDisplayMessageBody());
                            sms.put("timestamp", msg.getTimestampMillis());
                            new Handler(Looper.getMainLooper()).post(() -> {
                                if (eventSink != null) eventSink.success(sms);
                            });
                        }
                    }
                }
            };
            
            IntentFilter filter = new IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                appContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
            } else {
                appContext.registerReceiver(receiver, filter);
            }
        }

        @Override
        public void onCancel(Object arguments) {
            if (receiver != null) {
                try {
                    appContext.unregisterReceiver(receiver);
                } catch (IllegalArgumentException ignored) {}
            }
            eventSink = null;
        }
    }
}