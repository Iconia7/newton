import 'package:newton/models/ussd_data_plan.dart';
import 'package:flutter/material.dart'; // Added for debugPrint

class MessageProcessor {
  // Regex to extract amount. Looks for "Ksh" followed by digits, optional comma, and two decimal places.
  // It handles text before "Ksh" and spaces after the amount before "received from".
  static final RegExp _amountPattern = RegExp(
    r'Ksh(\d{1,3}(?:,\d{3})*\.\d{2})\s*received from', // Adjusted to handle thousands comma
    caseSensitive: false,
  );

  // New approach: Capture the phone number immediately after "received from"
  static final RegExp _phoneNumberPattern = RegExp(
    r'received from\s*(\d+)', // Captures the number right after "received from "
    caseSensitive: false,
  );

  // New approach: Capture the name immediately after the phone number
  static final RegExp _namePattern = RegExp(
    r'received from\s*\d+\s*([A-Za-z\s.]+?)(?=\.\s*New Account balance|$)', // Captures name after number, up to ". New Account balance" or end of string
    caseSensitive: false,
  );

  /// Formats a name to have proper capitalization (first letter uppercase, rest lowercase)
  static String _formatName(String name) {
    if (name.isEmpty) return name;

    // Split name into words, format each word, then join back
    return name
        .trim()
        .split(RegExp(r'\s+')) // Split by one or more whitespace characters
        .map((word) {
          if (word.isEmpty) return word;
          // Capitalize first letter, lowercase the rest
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' '); // Join with single space
  }

  static Map<String, dynamic>? processMessage(
    String messageBody,
    List<UssdDataPlan> dataPlans,
  ) {
    debugPrint("Processing message body: $messageBody");

    String? extractedPhoneNumber;
    double? extractedAmount;
    String? extractedName;
    String? purchasedOffer;

    // --- Extract Amount ---
    final amountMatch = _amountPattern.firstMatch(messageBody);
    if (amountMatch != null) {
      final amountString = amountMatch.group(1)?.replaceAll(',', '');
      extractedAmount = double.tryParse(amountString ?? '');
      debugPrint("Extracted Amount: $extractedAmount");
    }

    // --- Extract Phone Number ---
    final phoneNumberMatch = _phoneNumberPattern.firstMatch(messageBody);
    if (phoneNumberMatch != null) {
      extractedPhoneNumber = phoneNumberMatch.group(1);
      if (extractedPhoneNumber != null) {
        // Normalize extracted phone number to 254 format
        if (extractedPhoneNumber.startsWith('0') &&
            extractedPhoneNumber.length == 10) {
          extractedPhoneNumber = '254${extractedPhoneNumber.substring(1)}';
        } else if (extractedPhoneNumber.startsWith('+254')) {
          extractedPhoneNumber = extractedPhoneNumber.substring(
            1,
          ); // Remove '+'
        }
        debugPrint("Extracted Phone Number: $extractedPhoneNumber");
      }
    }

    // --- Extract Name ---
    final nameMatch = _namePattern.firstMatch(messageBody);
    if (nameMatch != null) {
      extractedName = nameMatch.group(1)?.trim();
      // Remove any leading/trailing periods or spaces from the name
      if (extractedName != null) {
        extractedName = extractedName.replaceAll(RegExp(r'^\.|\.$'), '').trim();
        // Format the name with proper capitalization
        extractedName = _formatName(extractedName);
      }
      debugPrint("Extracted Name: $extractedName");
    }

    // Match amount to data plans
    bool amountMatched = false;
    if (extractedAmount != null) {
      for (final plan in dataPlans) {
        if (plan.amount == extractedAmount) {
          purchasedOffer = plan.planName;
          debugPrint(
            "Matched Offer: $purchasedOffer for amount $extractedAmount",
          );
          break;
        }
      }
      if (!amountMatched) {
        return {
          'amount': extractedAmount,
          'phoneNumber': extractedPhoneNumber,
          'name': extractedName,
          'status': 'no_offer', // Special status for unmatched amounts
        };
      }
    }

    // --- Return Results ---
    // Ensure both amount and phone number are extracted for a valid transaction
    if (extractedAmount != null && extractedPhoneNumber != null) {
      return {
        'amount': extractedAmount,
        'phoneNumber': extractedPhoneNumber,
        'name': extractedName,
        'purchasedOffer': purchasedOffer, // Can be null if not found
      };
    }
    debugPrint(
      "Failed to extract sufficient data (amount or phone number missing).",
    );
    return null;
  }

  // --- USSD Code Preparation ---
  static String? prepareUssdCode(UssdDataPlan plan, String phoneNumber) {
    String formattedPhoneNumberForUssd = phoneNumber;
    if (phoneNumber.startsWith('254') && phoneNumber.length == 12) {
      formattedPhoneNumberForUssd = '0${phoneNumber.substring(3)}';
    } else if (phoneNumber.startsWith('+254') && phoneNumber.length == 13) {
      formattedPhoneNumberForUssd = '0${phoneNumber.substring(4)}';
    }

    String ussdCode = plan.ussdCodeTemplate;

    if (ussdCode.contains(plan.placeholder)) {
      ussdCode = ussdCode.replaceAll(
        plan.placeholder,
        formattedPhoneNumberForUssd,
      );
    } else {
      return null; // Placeholder not found, invalid template
    }

    return ussdCode;
  }
}
