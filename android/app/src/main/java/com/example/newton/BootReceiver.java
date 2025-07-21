package com.example.newton;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.preference.PreferenceManager;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent.getAction().equals(Intent.ACTION_BOOT_COMPLETED)) {
            // Load keywords from SharedPreferences
            SharedPreferences prefs = PreferenceManager.getDefaultSharedPreferences(context);
            
            // Load success keywords
            Set<String> successSet = prefs.getStringSet("successKeywords", new HashSet<String>());
            List<String> successKeywords = new ArrayList<>(successSet);
            
            // Load failure keywords
            Set<String> failureSet = prefs.getStringSet("failureKeywords", new HashSet<String>());
            List<String> failureKeywords = new ArrayList<>(failureSet);
            
            // Start service with loaded keywords
            BackgroundService.startBackgroundService(context, successKeywords, failureKeywords);
        }
    }
}