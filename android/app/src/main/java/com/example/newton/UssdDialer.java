package com.example.newton;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.telephony.SubscriptionInfo;
import android.telephony.SubscriptionManager;
import android.telephony.TelephonyManager;
import android.util.Log;

import java.util.List;

import io.flutter.plugin.common.MethodChannel;

public class UssdDialer {
    private static final String TAG = "UssdDialer";

    public static void dialUssd(Context context, String ussdCode, int simSlot, MethodChannel.Result result, MethodChannel ussdMethodChannel) {
        try {
            SubscriptionManager subscriptionManager = SubscriptionManager.from(context);
            List<SubscriptionInfo> subscriptionInfoList = subscriptionManager.getActiveSubscriptionInfoList();

            if (subscriptionInfoList == null || simSlot >= subscriptionInfoList.size()) {
                result.error("SIM_ERROR", "Invalid SIM slot: " + simSlot, null);
                return;
            }

            SubscriptionInfo simInfo = subscriptionInfoList.get(simSlot);
            int subId = simInfo.getSubscriptionId();

            TelephonyManager baseManager = (TelephonyManager) context.getSystemService(Context.TELEPHONY_SERVICE);
            TelephonyManager simTelephonyManager = baseManager.createForSubscriptionId(subId);

            if (simTelephonyManager == null) {
                result.error("TELEPHONY_MANAGER_NULL", "No TelephonyManager for SIM slot: " + simSlot, null);
                return;
            }

            simTelephonyManager.sendUssdRequest(
                ussdCode,
                new TelephonyManager.UssdResponseCallback() {
                    @Override
                    public void onReceiveUssdResponse(TelephonyManager tm, String request, CharSequence response) {
                        new Handler(Looper.getMainLooper()).post(() -> {
                            if (ussdMethodChannel != null) {
                                ussdMethodChannel.invokeMethod("onUssdResponse", response.toString());
                            }
                        });
                    }

                    @Override
                    public void onReceiveUssdResponseFailed(TelephonyManager tm, String request, int failureCode) {
                        new Handler(Looper.getMainLooper()).post(() -> {
                            if (ussdMethodChannel != null) {
                                ussdMethodChannel.invokeMethod("onUssdError", "USSD failed (code " + failureCode + ")");
                            }
                        });
                    }
                },
                new Handler(Looper.getMainLooper())
            );

            result.success("USSD triggered via SIM " + simSlot);
        } catch (Exception e) {
            Log.e(TAG, "USSD dial failed: " + e.getMessage(), e);
            result.error("USSD_DIAL_FAILED", "Could not dial USSD: " + e.getMessage(), null);
        }
    }
}