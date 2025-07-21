package com.example.newton;

import android.app.Notification;
import io.flutter.plugin.common.MethodChannel;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.provider.Telephony;
import android.util.Log;
import androidx.core.app.NotificationCompat;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class BackgroundService extends Service {
    private static final String TAG = "BackgroundService";
    private static final String CHANNEL_ID = "bingwa_sokoni_background";
    private static final String CHANNEL_NAME = "Bingwa Sokoni Background Service";
    private static final int NOTIFICATION_ID = 888;
    private static final long TASK_INTERVAL = 2 * 60 * 1000; // 2 minutes
    
    private Handler handler;
    private Runnable backgroundTask;
    private FlutterEngine flutterEngine;
    private MethodChannel methodChannel;
    private SmsBroadcastReceiver smsReceiver;
    private List<String> successKeywords = new ArrayList<>();
    private List<String> failureKeywords = new ArrayList<>();

    @Override
    public void onCreate() {
        super.onCreate();
        Log.d(TAG, "Background service created");
        
        createNotificationChannel();
        initializeFlutterEngine();
        registerSmsReceiver();
        setupBackgroundTask();
    }

    private void registerSmsReceiver() {
        smsReceiver = new SmsBroadcastReceiver();
        smsReceiver.setBackgroundMode(true);
        IntentFilter filter = new IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION);
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            registerReceiver(smsReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(smsReceiver, filter);
        }
        Log.d(TAG, "SMS receiver registered for background processing");
    }
    
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.d(TAG, "Background service started");
        
        // Handle keyword updates
        if (intent != null && intent.hasExtra("successKeywords")) {
            successKeywords = intent.getStringArrayListExtra("successKeywords");
            failureKeywords = intent.getStringArrayListExtra("failureKeywords");
            Log.d(TAG, "Keywords updated: " + successKeywords + ", " + failureKeywords);
        }
        
        // Start foreground service
        startForeground(NOTIFICATION_ID, createNotification("Service is active"));
        
        // Start background task
        if (handler != null && backgroundTask != null) {
            handler.post(backgroundTask);
        }
        
        return START_STICKY;
    }
    
    @Override
    public void onDestroy() {
        super.onDestroy();
        Log.d(TAG, "Background service destroyed");
        
        // Clean up resources
        if (handler != null && backgroundTask != null) {
            handler.removeCallbacks(backgroundTask);
        }
        
        if (flutterEngine != null) {
            flutterEngine.destroy();
        }
        
        if (smsReceiver != null) {
            try {
                unregisterReceiver(smsReceiver);
            } catch (IllegalArgumentException e) {
                Log.w(TAG, "Receiver was not registered: " + e.getMessage());
            }
        }
    }
    
    @Override
    public IBinder onBind(Intent intent) {
        return null; // We don't provide binding
    }
    
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("Background service for Bingwa Sokoni app");
            channel.setSound(null, null);
            channel.enableVibration(false);
            channel.setShowBadge(false);
            
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.createNotificationChannel(channel);
            }
        }
    }
    
    private Notification createNotification(String content) {
        // Create intent for when notification is tapped
        Intent notificationIntent = new Intent(this, MainActivity.class);
        PendingIntent pendingIntent = PendingIntent.getActivity(
            this, 
            0, 
            notificationIntent, 
            PendingIntent.FLAG_IMMUTABLE
        );
        
        return new NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Bingwa Sokoni")
            .setContentText(content)
            .setSmallIcon(R.drawable.ic_stat_bs)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .build();
    }
    
    private void initializeFlutterEngine() {
        try {
            flutterEngine = new FlutterEngine(this);
            flutterEngine.getDartExecutor().executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            );
            
            // Initialize method channel
            methodChannel = new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                "com.example.newton/background_service"
            );
            
            // Set up method call handler
            methodChannel.setMethodCallHandler((call, result) -> {
                switch (call.method) {
                    case "performBackgroundTask":
                        performBackgroundTask();
                        result.success("Task performed");
                        break;
                    case "stopService":
                        stopSelf();
                        result.success("Service stopped");
                        break;
                    case "updateKeywords":
                        Map<String, List<String>> keywords = call.argument("keywords");
                        if (keywords != null) {
                            successKeywords = keywords.get("successKeywords");
                            failureKeywords = keywords.get("failureKeywords");
                            result.success("Keywords updated");
                        } else {
                            result.error("INVALID_ARGUMENTS", "Missing keywords", null);
                        }
                        break;
                    default:
                        result.notImplemented();
                        break;
                }
            });
            
            Log.d(TAG, "Flutter engine initialized successfully");
        } catch (Exception e) {
            Log.e(TAG, "Failed to initialize Flutter engine: " + e.getMessage());
        }
    }
    
    private void setupBackgroundTask() {
        handler = new Handler(Looper.getMainLooper());
        backgroundTask = new Runnable() {
            @Override
            public void run() {
                try {
                    // Update notification
                    updateNotification("Running in background ...");
                    
                    // Perform background work
                    performBackgroundTask();
                    
                    // Schedule next execution
                    handler.postDelayed(this, TASK_INTERVAL);
                    
                } catch (Exception e) {
                    Log.e(TAG, "Background task error: " + e.getMessage());
                    // Continue running even if there's an error
                    handler.postDelayed(this, TASK_INTERVAL);
                }
            }
        };
    }
    
    private void updateNotification(String content) {
        NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager != null) {
            manager.notify(NOTIFICATION_ID, createNotification(content));
        }
    }
    
    private void performBackgroundTask() {
        Log.d(TAG, "Performing background task");
        
        try {
            // Check for new SMS in receiver
            if (smsReceiver != null) {
                smsReceiver.processStoredMessages(BackgroundService.this);
            }
            
            // Send status update
            sendStatusUpdate();
            
        } catch (Exception e) {
            Log.e(TAG, "Error in performBackgroundTask: " + e.getMessage());
        }
    }
    
    private void sendStatusUpdate() {
        Log.d(TAG, "Status update sent at: " + System.currentTimeMillis());
    }
    
    public void handleSmsInBackground(String sender, String body, long timestamp) {
        Log.d(TAG, "Processing SMS in background: " + sender + " - " + body);
        
        try {
            if (methodChannel != null) {
                Map<String, Object> smsData = new HashMap<>();
                smsData.put("sender", sender);
                smsData.put("body", body);
                smsData.put("timestamp", timestamp);
                
                methodChannel.invokeMethod("handleBackgroundSms", smsData);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error handling SMS: " + e.getMessage());
        }
    }
    
    // Static method to start the service
    public static void startBackgroundService(Context context, List<String> successKeywords, List<String> failureKeywords) {
        Intent serviceIntent = new Intent(context, BackgroundService.class);
        serviceIntent.putStringArrayListExtra("successKeywords", new ArrayList<>(successKeywords));
        serviceIntent.putStringArrayListExtra("failureKeywords", new ArrayList<>(failureKeywords));
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent);
        } else {
            context.startService(serviceIntent);
        }
    }
    
    // Static method to stop the service
    public static void stopBackgroundService(Context context) {
        Intent serviceIntent = new Intent(context, BackgroundService.class);
        context.stopService(serviceIntent);
    }
}