// ignore_for_file: empty_catches, unused_catch_clause

import 'package:flutter/services.dart';
import 'dart:async';

import 'package:newton/services/database_helper.dart';
import 'package:newton/services/message_processor.dart';
import 'package:newton/models/ussd_data_plan.dart';
import 'package:newton/services/shared_preferences_helper.dart';

class PlatformChannels {
  static const EventChannel smsEventChannel = EventChannel(
    'com.example.newton/smsEvent',
  );

  static const MethodChannel ussdChannel = MethodChannel(
    'com.example.newton/ussd',
  );

  static const MethodChannel simChannel = MethodChannel(
    'com.example.newton/sim',
  );

  static const MethodChannel smsSenderChannel = MethodChannel(
    'com.example.newton/sms_sender',
  );

  static const MethodChannel serviceControlChannel = MethodChannel(
    'com.example.newton/service_control',
  );

  static const MethodChannel backgroundSmsChannel = MethodChannel(
    'com.example.newton/backgroundSms',
  );
  static const MethodChannel _ussdChannel = MethodChannel(
    'com.example.newton/ussd',
  );

  static final _ussdResponseController = StreamController<String>.broadcast();
  static final _ussdErrorController = StreamController<String>.broadcast();

  static Stream<String> get ussdResponseStream =>
      _ussdResponseController.stream;
  static Stream<String> get ussdErrorStream => _ussdErrorController.stream;

  static bool _ussdMethodCallHandlerInitialized = false;

  static void initUssdMethodCallHandler() {
    if (!_ussdMethodCallHandlerInitialized) {
      ussdChannel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'onUssdResponse':
            final String response = call.arguments as String;
            _ussdResponseController.add(response);
            break;
          case 'onUssdError':
            final String errorMessage = call.arguments as String;
            _ussdErrorController.add(errorMessage);
            break;
          default:
            throw PlatformException(
              code: 'UNIMPLEMENTED_METHOD',
              message: 'Method ${call.method} not implemented in Dart',
            );
        }
      });
      _ussdMethodCallHandlerInitialized = true;
    }
  }

  // Add this method to listen for USSD responses
  static void setUssdResponseHandler(
    Function(Map<String, dynamic>) onResponse,
  ) {
    _ussdChannel.setMethodCallHandler((call) async {
      if (call.method == 'onUssdResponse') {
        final response = Map<String, dynamic>.from(call.arguments);
        onResponse(response);
      } else if (call.method == 'onUssdError') {
        final error = call.arguments.toString();
        onResponse({'error': error, 'isSuccess': false, 'isFailure': true});
      }
    });
  }

  /// Triggers a USSD code.
  static Future<void> triggerUssd(
    String ussdCode,
    int? simSubscriptionId,
    Map<String, dynamic>? transaction,
  ) async {
    try {} on PlatformException catch (e) {
      throw PlatformException(
        code: e.code,
        message: "USSD request failed: ${e.message}",
        details: e.details,
      );
    }
  }

  static Future<List<Map<String, dynamic>>> getSimCards() async {
    try {
      final List<dynamic>? simCards = await simChannel.invokeMethod(
        'getSimCards',
      );
      if (simCards != null) {
        return simCards
            .cast<Map<dynamic, dynamic>>()
            .map((sim) => Map<String, dynamic>.from(sim))
            .toList();
      }
      return [];
    } on PlatformException catch (e) {
      throw Exception("Failed to get SIM cards: ${e.message}");
    }
  }

  static Future<bool> sendSms(
    String recipientAddress,
    String messageBody,
  ) async {
    try {
      final result = await smsSenderChannel.invokeMethod('sendSms', {
        'recipientAddress': recipientAddress,
        'messageBody': messageBody,
      });
      return result as bool;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> startSmsService() async {
    try {
      await serviceControlChannel.invokeMethod('startService');
    } on PlatformException {}
  }

  static Future<void> stopSmsService() async {
    try {
      await serviceControlChannel.invokeMethod('stopService');
    } on PlatformException catch (e) {}
  }

  static void dispose() {
    _ussdResponseController.close();
    _ussdErrorController.close();
    _ussdMethodCallHandlerInitialized = false;
  }

  @pragma('vm:entry-point')
  static Future<void> backgroundSmsHandler() async {
    final DatabaseHelper dbHelper = DatabaseHelper();
    final SharedPreferencesHelper prefsHelper = SharedPreferencesHelper();

    backgroundSmsChannel.setMethodCallHandler((call) async {
      if (call.method == 'handleBackgroundSms') {
        final Map<String, dynamic> smsData = Map<String, dynamic>.from(
          call.arguments as Map,
        );

        final String sender = smsData['sender'] as String;
        final String body = smsData['body'] as String;
        final int timestamp = smsData['timestamp'] as int;

        await dbHelper.insertMessage({
          'sender': sender,
          'body': body,
          'timestamp': timestamp,
        });

        final String mpesaSender = 'MPESA';
        final String requiredKeyword = 'Confirmed.on';

        // Load data plans from database for background processing
        final List<UssdDataPlan> dataPlans = await dbHelper.getUssdDataPlans();

        if (sender.toUpperCase().contains(mpesaSender) &&
            body.contains(requiredKeyword)) {
          final extracted = MessageProcessor.processMessage(body, dataPlans);

          if (extracted != null) {
            final amount = extracted['amount'] as double?;
            final phone = extracted['phoneNumber'] as String?;
            final name = extracted['name'] as String?;

            if (amount != null && phone != null) {
              UssdDataPlan? matchingPlan;
              for (final plan in dataPlans) {
                if (plan.amount == amount) {
                  matchingPlan = plan;
                  break;
                }
              }
              if (matchingPlan != null) {
                final code = MessageProcessor.prepareUssdCode(
                  matchingPlan,
                  phone,
                );
                if (code != null) {
                  final simId = await prefsHelper.getSelectedSimId();
                  if (simId != null) {
                    try {
                      // Attempt to trigger USSD
                      await PlatformChannels.triggerUssd(code, simId, {
                        'extractedPhoneNumber': phone,
                        'extractedAmount': amount,
                        'extractedName': name,
                        'purchasedOffer': matchingPlan.planName,
                      });
                    } catch (_) {
                      _sendAutoSms(phone, _getSmsMessage(false, amount, name));
                    }
                  } else {
                    _sendAutoSms(phone, _getSmsMessage(false, amount, name));
                  }
                } else {
                  _sendAutoSms(phone, _getSmsMessage(false, amount, name));
                }
              } else {
                _sendAutoSms(phone, _getSmsMessage(false, amount, name));
              }
            }
          }
        } else if (body.toLowerCase().contains("Recommendation failed")) {
          // Failure detected, send failure SMS
          final extracted = MessageProcessor.processMessage(body, []);
          final amount = extracted?['amount'] as double?;
          final phone = extracted?['phoneNumber'] as String?;
          final name = extracted?['name'] as String?;

          if (phone != null) {
            _sendAutoSms(phone, _getSmsMessage(false, amount, name));
          }
        }
        return true;
      }
      return false;
    });
  }
}

// Helper functions

String _getSmsMessage(bool isSuccess, double? amount, String? name) {
  final displayAmount =
      amount != null ? 'Ksh${amount.toStringAsFixed(2)}' : 'N/A';
  final recipient = name ?? 'customer';

  return isSuccess
      ? 'Hello $recipient,\nYour data bundle purchase of $displayAmount was successful. Thank you for your business!'
      : 'Hello $recipient,\nThere was an issue processing your data bundle purchase of $displayAmount. Please try again or contact support.';
}

Future<void> _sendAutoSms(String recipient, String message) async {
  try {} catch (e) {}
}
