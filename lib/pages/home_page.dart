// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:newton/main.dart';
import 'package:newton/models/transaction.dart';
import 'package:newton/pages/Settings.dart';
import 'package:newton/pages/buy_tokens_screen.dart';
import 'package:newton/pages/transaction_details_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:newton/services/database_helper.dart';
import 'package:newton/services/message_processor.dart';
import 'package:newton/platform_channels.dart';
import 'package:newton/models/ussd_data_plan.dart';
import 'package:newton/services/shared_preferences_helper.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:newton/pages/all_transactions_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class HomeContent extends StatefulWidget {
  final String userId; // Now required
  const HomeContent({super.key, required this.userId});
  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> with TickerProviderStateMixin {
  List<Map<String, dynamic>> _filteredTransactions = [];
  List<UssdDataPlan> _dataPlans = [];
  List<Transactions> _successfulTransactions = [];
  List<Transactions> _failedTransactions = [];
  List<String> _successKeywords = ['activated', 'successfully', 'purchased'];
  List<String> _failureKeywords = ['failed', 'insufficient', 'error'];
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SharedPreferencesHelper _prefsHelper = SharedPreferencesHelper();
  late AnimationController _fadeController;
  late AnimationController _slideController;

  static const String mpesaSender = 'MPESA';
  static const String requiredKeyword = 'Confirmed.on';

  // Add these constants at the top of your class
  static const Color snowWhite = Color(0xFFFCF7F8);
  static const Color madderRed = Color.fromARGB(0, 19, 106, 133);

  int? _selectedSimSubscriptionId;
  String _airtimeBalance = 'Tap to Check';
  bool _isCheckingBalance = false;
  bool _isBalanceVisible = true;
  bool _isRefreshingTokens = false;
  StreamSubscription<dynamic>? _smsSubscription;
  StreamSubscription<String>? _ussdResponseSubscription;
  StreamSubscription<String>? _ussdErrorSubscription;

  Timer? _balanceCheckTimeoutTimer;
  Timer? _midnightClearTimer; // Timer to clear transactions at midnight

  Map<String, dynamic>? _currentAutoBuyMpesaTransaction;

  @override
  void initState() {
    super.initState();
    _setupUssdResponseListener();
    Future.delayed(Duration.zero, () {
      _refreshTokenBalance();
    });
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );

    // Trigger animations
    _fadeController.forward();
    _slideController.forward();
    _initializeApp();
    _setupMidnightClearTimer();
    _loadTransactions();
    _successfulTransactions = [];
    _failedTransactions = [];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkMidnightClear();
      _loadKeywords();
      _loadStoredTransactions(); // Add this after first frame
    }); // Set up the midnight clear timer
  }

  @override
  void dispose() {
    _smsSubscription?.cancel();
    _fadeController.dispose();
    _slideController.dispose();
    _ussdResponseSubscription?.cancel();
    _ussdErrorSubscription?.cancel();
    _balanceCheckTimeoutTimer?.cancel();
    _midnightClearTimer?.cancel();
    PlatformChannels.ussdChannel.setMethodCallHandler(
      null,
    ); // Cancel the midnight clear timer
    super.dispose();
  }

  Future<void> _initializeApp() async {
    await _requestPermissions();
    await _loadDataPlans();
    await _loadFilteredTransactions();
    await _loadSelectedSim();
    _listenForSms();
    PlatformChannels.initUssdMethodCallHandler();
    _listenForUssdResponses();
  }

  Future<void> _loadTransactions() async {
    final transactions = await _dbHelper.getAllTransactions();
    setState(() {
      _successfulTransactions = transactions.where((t) => t.isSuccess).toList();
      _failedTransactions = transactions.where((t) => !t.isSuccess).toList();
    });
  }

  Future<void> _refreshTokenBalance() async {
    if (_isRefreshingTokens) return;

    setState(() {
      _isRefreshingTokens = true;
    });

    try {
      // First try to get updated balance from server
      final userId = UserManager.getCurrentUserId();
      if (userId != null) {
        await _fetchTokenBalanceFromServer(userId);
        setState(() {});
      }

      // Also retry registration if needed
      if (!(await UserManager.isUserRegistered())) {
        await UserManager.retryRegistration();
      }

      // Refresh the UI
      setState(() {});
    } catch (e) {
      debugPrint('Error refreshing token balance: $e');

      // Show snackbar for user feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh token balance'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingTokens = false;
        });
      }
    }
  }

  Future<void> _fetchTokenBalanceFromServer(String userId) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://bingwa-sokoni-app.onrender.com/api/users/$userId/tokens',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['tokenBalance'] != null) {
          // Update cached token balance
          await UserManager.updateCachedTokenBalance(data['tokenBalance']);
          debugPrint('✅ Token balance updated: ${data['tokenBalance']}');
        }
      } else {
        debugPrint('❌ Failed to fetch token balance: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching token balance: $e');
      rethrow;
    }
  }

  Future<bool> _deductTokenForUssd() async {
    try {
      final userId = UserManager.getCurrentUserId();
      if (userId == null) return false;

      // First check current balance
      final currentBalance = await UserManager.getCachedTokenBalance() ?? 0;
      if (currentBalance <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Insufficient tokens. Please buy more tokens.'),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Buy Tokens',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) =>
                              PaymentScreen(userId: userId, customerName: ''),
                    ),
                  );
                },
              ),
            ),
          );
        }
        return false;
      }

      // Deduct token on server
      final response = await http
          .post(
            Uri.parse(
              'https://bingwa-sokoni-app.onrender.com/api/users/$userId/deduct-token',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({
              'amount': 1, // Deduct 1 token per USSD trigger
              'reason': 'USSD trigger',
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // Update local cache
          await UserManager.updateCachedTokenBalance(data['newBalance']);

          // Refresh UI
          if (mounted) {
            setState(() {});

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Token deducted. Remaining: ${data['newBalance']}',
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }

          debugPrint(
            '✅ Token deducted successfully. New balance: ${data['newBalance']}',
          );
          return true;
        }
      }

      debugPrint('❌ Failed to deduct token: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('❌ Error deducting token: $e');
      return false;
    }
  }

  Future<void> _addTokensAfterPurchase(int tokensToAdd) async {
    try {
      final currentBalance = await UserManager.getCachedTokenBalance() ?? 0;
      final newBalance = currentBalance + tokensToAdd;

      // Update local cache immediately for responsive UI
      await UserManager.updateCachedTokenBalance(newBalance);

      // Refresh UI
      if (mounted) {
        setState(() {});
      }

      debugPrint('✅ Added $tokensToAdd tokens. New balance: $newBalance');
    } catch (e) {
      debugPrint('❌ Error adding tokens: $e');
    }
  }

  Future<void> _processTransactionResponse(
    bool isSuccess,
    bool isFailure,
  ) async {
    final transaction = _currentAutoBuyMpesaTransaction!;

    await _storeTransaction(
      transaction['extractedName']!,
      transaction['extractedAmount']!,
      transaction['extractedPhoneNumber']!,
      isSuccess,
    );
    _currentAutoBuyMpesaTransaction = null;
    await _loadTransactions();
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses =
        await [Permission.sms, Permission.phone].request();

    if (statuses.containsKey(Permission.sms) &&
        statuses.containsKey(Permission.phone)) {
      if (statuses.values.every((status) => status.isGranted)) {
      } else {
        String missingPermissions = '';
        if (statuses[Permission.sms]?.isDenied == true) {
          missingPermissions += 'SMS';
        }
        if (statuses[Permission.phone]?.isDenied == true) {
          if (missingPermissions.isNotEmpty) missingPermissions += ' and ';
          missingPermissions += 'Phone';
        }
        _showSnackbar(
          '$missingPermissions permissions are required for full functionality.',
          isError: true,
        );
      }
    }
  }

  Future<void> _loadStoredTransactions() async {
    final successes = await _dbHelper.getSuccessfulTransactions();
    final failures = await _dbHelper.getFailedTransactions();

    setState(() {
      _successfulTransactions = successes;
      _failedTransactions = failures;
    });
  }

  Future<void> _loadDataPlans() async {
    _dataPlans = await _dbHelper.getUssdDataPlans();
  }

  Future<void> _loadKeywords() async {
    final prefs = await SharedPreferences.getInstance();
    final successKeywordsStr =
        prefs.getString('keyword_success') ?? 'activated,success,purchased';
    final failureKeywordsStr =
        prefs.getString('keyword_failure') ?? 'failed,insufficient,error';

    setState(() {
      _successKeywords =
          successKeywordsStr
              .split(',')
              .map((e) => e.trim().toLowerCase())
              .toList();
      _failureKeywords =
          failureKeywordsStr
              .split(',')
              .map((e) => e.trim().toLowerCase())
              .toList();
    });
  }

  Future<void> _checkMidnightClear() async {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final lastClearDate = await _prefsHelper.getLastClearDate();

    if (lastClearDate != todayStr) {
      await _clearTransactions();
      await _prefsHelper.setLastClearDate(todayStr);
    }
  }

  Future<void> _loadSelectedSim() async {
    _selectedSimSubscriptionId = await _prefsHelper.getSelectedSimId();
    if (_selectedSimSubscriptionId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSimSelectionDialog();
      });
    }
  }

  Future<void> _showSimSelectionDialog() async {
    if (await Permission.phone.isGranted) {
      List<Map<String, dynamic>> simCards = [];
      try {
        simCards = await PlatformChannels.getSimCards();
      } on PlatformException catch (e) {
        _showSnackbar("Failed to retrieve SIMs: ${e.message}", isError: true);
        return;
      } catch (e) {
        _showSnackbar(
          "An unexpected error occurred while getting SIMs: $e",
          isError: true,
        );
        return;
      }

      if (!mounted) return;

      if (simCards.isEmpty) {
        _showSnackbar(
          'No active SIM cards found. Cannot select a SIM for USSD.',
          isError: true,
        );
        return;
      }

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                elevation: 24,
                backgroundColor: Colors.transparent,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.9,
                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                  ),
                  decoration: BoxDecoration(
                    color: snowWhite,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [madderRed, madderRed.withOpacity(0.8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.sim_card_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                'Select SIM for USSD',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Content
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Choose which SIM card to use for USSD operations:',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: madderRed.withOpacity(0.7),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // SIM Cards List
                              Flexible(
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: simCards.length,
                                  separatorBuilder:
                                      (context, index) =>
                                          const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final sim = simCards[index];
                                    final isSelected =
                                        _selectedSimSubscriptionId ==
                                        sim['subscriptionId'];

                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: () {
                                          setDialogState(() {
                                            _selectedSimSubscriptionId =
                                                sim['subscriptionId'] as int;
                                          });
                                          setState(() {
                                            _selectedSimSubscriptionId =
                                                sim['subscriptionId'] as int;
                                          });
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color:
                                                isSelected
                                                    ? snowWhite.withOpacity(0.1)
                                                    : snowWhite,
                                            border: Border.all(
                                              color:
                                                  isSelected
                                                      ? madderRed
                                                      : madderRed.withOpacity(
                                                        0.3,
                                                      ),
                                              width: isSelected ? 2 : 1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      isSelected
                                                          ? madderRed
                                                          : madderRed
                                                              .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Icon(
                                                  Icons.sim_card_outlined,
                                                  size: 20,
                                                  color:
                                                      isSelected
                                                          ? Colors.white
                                                          : madderRed
                                                              .withOpacity(0.6),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      sim['displayName'] ??
                                                          'Unknown SIM',
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 16,
                                                            color:
                                                                isSelected
                                                                    ? madderRed
                                                                    : madderRed,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      'Slot ${(sim['simSlotIndex'] ?? 0) + 1}',
                                                      style:
                                                          GoogleFonts.poppins(
                                                            fontSize: 14,
                                                            color: madderRed
                                                                .withOpacity(
                                                                  0.6,
                                                                ),
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              AnimatedScale(
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                scale: isSelected ? 1.0 : 0.0,
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: madderRed,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.check,
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Actions
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: snowWhite,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(24),
                            bottomRight: Radius.circular(24),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: snowWhite.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: madderRed.withOpacity(0.3),
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    color: madderRed.withOpacity(0.7),
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: madderRed,
                                  foregroundColor: snowWhite,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Confirm Selection',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                onPressed: () async {
                                  if (_selectedSimSubscriptionId != null) {
                                    await _prefsHelper.saveSelectedSimId(
                                      _selectedSimSubscriptionId!,
                                    );
                                    final selectedSimInfo = simCards.firstWhere(
                                      (s) =>
                                          s['subscriptionId'] ==
                                          _selectedSimSubscriptionId,
                                      orElse:
                                          () => {'displayName': 'Unknown SIM'},
                                    );
                                    _showSnackbar(
                                      'SIM selected for USSD: ${selectedSimInfo['displayName']}',
                                    );
                                    Navigator.of(dialogContext).pop();
                                  } else {
                                    _showSnackbar(
                                      'Please select a SIM card.',
                                      isError: true,
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
      setState(() {});
    } else {
      _showSnackbar(
        'Phone permission not granted. Cannot list SIMs for selection.',
        isError: true,
      );
    }
  }

  Future<void> _loadFilteredTransactions() async {
    final allMessages = await _dbHelper.getMessages();
    List<Map<String, dynamic>> tempFilteredMessages = [];

    for (var message in allMessages) {
      final String sender = message['sender'] ?? '';
      final String body = message['body'] ?? '';
      final String normalizedSender = sender.toUpperCase();

      // Handle no_offer status first
      if (message['status'] == 'no_offer') {
        // Use stored extracted data if available
        if (message['extractedName'] != null) {
          tempFilteredMessages.add(message);
        }
        continue;
      }
      if (normalizedSender.contains(mpesaSender.toUpperCase()) &&
          body.contains(requiredKeyword)) {
        final extractedData = MessageProcessor.processMessage(body, _dataPlans);
        if (extractedData != null &&
            extractedData['amount'] != null &&
            extractedData['name'] != null) {
          Map<String, dynamic> mutableMessage = Map<String, dynamic>.from(
            message,
          );

          mutableMessage['extractedName'] = extractedData['name'];
          mutableMessage['extractedAmount'] = extractedData['amount'];
          mutableMessage['extractedPhoneNumber'] = extractedData['phoneNumber'];
          mutableMessage['purchasedOffer'] = extractedData['purchasedOffer'];
          tempFilteredMessages.add(mutableMessage);
        }
      }
    }

    setState(() {
      tempFilteredMessages.sort(
        (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
      );
      _filteredTransactions = tempFilteredMessages;
    });
  }

  void _listenForSms() {
    _smsSubscription = PlatformChannels.smsEventChannel
        .receiveBroadcastStream()
        .listen((event) async {
          final Map<String, dynamic> messageData = Map<String, dynamic>.from(
            event as Map,
          );

          final String sender = messageData['sender'] as String;
          final String body = messageData['body'] as String;
          final int timestamp = messageData['timestamp'] as int;

          await _dbHelper.insertMessage({
            'sender': sender,
            'body': body,
            'timestamp': timestamp,
          });

          await _loadFilteredTransactions();

          if (_isCheckingBalance &&
              sender.toLowerCase().contains('safaricom')) {
            _processReceivedSms(sender, body);
          }

          final String normalizedSender = sender.toUpperCase();
          if (normalizedSender.contains(mpesaSender.toUpperCase()) &&
              body.contains(requiredKeyword)) {
            final extractedData = MessageProcessor.processMessage(
              body,
              _dataPlans,
            );
            if (extractedData != null) {
              final double? amount = extractedData['amount'];
              final String? phoneNumber = extractedData['phoneNumber'];
              final String? name = extractedData['name'];
              if (amount != null) {
                for (final plan in _dataPlans) {
                  if (plan.amount == amount) {
                    break;
                  }
                }
              }
              if (name != null) {}
              if (phoneNumber != null) {}

              if (amount != null && phoneNumber != null) {
                final UssdDataPlan? matchingPlan = await _dbHelper
                    .getUssdDataPlanByAmount(amount);

                if (matchingPlan != null) {
                  final String? finalUssdCode =
                      MessageProcessor.prepareUssdCode(
                        matchingPlan,
                        phoneNumber,
                      );
                  if (finalUssdCode != null) {
                    _currentAutoBuyMpesaTransaction = {
                      'sender': sender,
                      'body': body,
                      'timestamp': timestamp,
                      'extractedName': name,
                      'extractedAmount': amount,
                      'extractedPhoneNumber': phoneNumber,
                      'purchasedOffer': matchingPlan.planName,
                    };

                    await _triggerUssdAndNotify(
                      finalUssdCode,
                      _selectedSimSubscriptionId,
                      planName: matchingPlan.planName,
                      targetNumber: phoneNumber,
                    );
                  }
                } else {
                  // NEW: Handle no matching offer
                  _sendNoOfferSms(
                    phoneNumber: phoneNumber,
                    name: name!,
                    amount: amount,
                    sender: sender,
                    body: body,
                    timestamp: timestamp,
                  );
                }
              }
            }
          }
        });
  }

  // Add this helper function to extract first name
  String _getFirstName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return fullName;
    return parts[0];
  }

  Future<void> _sendNoOfferSms({
    required String phoneNumber,
    required String name,
    required double amount,
    required String sender,
    required String body,
    required int timestamp,
  }) async {
    try {
      // Get the "no offer" template from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final template =
          prefs.getString('sms_no_offer') ??
          "Sorry [first_name] 😔, the amount [amount] sent does not match any of our offers.\n"
              "Whatsapp 0115332870 to get list of our offers.";

      // Extract first name
      final firstName = _getFirstName(name);

      // Replace placeholders with actual values
      final message = template
          .replaceAll('[first_name]', firstName)
          .replaceAll('[amount]', 'Ksh${amount.toStringAsFixed(2)}')
          .replaceAll('[phone]', phoneNumber);

      // Send the SMS
      await PlatformChannels.sendSms(phoneNumber, message);

      // Update the transaction with no_offer status
      await _dbHelper.updateMessageStatus(timestamp, 'no_offer');

      // Reload transactions to show the updated status
      await _loadFilteredTransactions();
      // ignore: empty_catches
    } catch (e) {}
  }

  void _listenForUssdResponses() {
    PlatformChannels.ussdResponseStream.listen((response) {
      final responseLower = response.toLowerCase();
      bool isSuccess = _successKeywords.any((k) => responseLower.contains(k));
      bool isFailure = _failureKeywords.any((k) => responseLower.contains(k));

      if (_currentAutoBuyMpesaTransaction != null) {
        _processTransactionResponse(isSuccess, isFailure);
        _currentAutoBuyMpesaTransaction = null;
      }
    });

    PlatformChannels.ussdErrorStream.listen((error) {
      if (_currentAutoBuyMpesaTransaction != null) {}
    });
    _ussdResponseSubscription = PlatformChannels.ussdResponseStream.listen(
      (response) {
        _showSnackbar('USSD Response: $response');

        // Convert response to lowercase for case-insensitive matching
        final responseLower = response.toLowerCase();

        // Check for success keywords
        _successKeywords.any((k) => responseLower.contains(k));

        // Check for failure keywords
        _failureKeywords.any((k) => responseLower.contains(k));

        if (!_isCheckingBalance && _currentAutoBuyMpesaTransaction != null) {
          // ignore: unused_local_variable
          final double? extractedAmount =
              _currentAutoBuyMpesaTransaction?['extractedAmount'];
          // ignore: unused_local_variable
          final String? extractedName =
              _currentAutoBuyMpesaTransaction?['extractedName'];

          _currentAutoBuyMpesaTransaction = null;
        }

        if (_isCheckingBalance && response.toLowerCase().contains('bal')) {
          _processReceivedSms('Safaricom', response);
        }
      },
      onError: (error) {
        _showSnackbar('USSD Response Stream Error: $error', isError: true);

        if (!_isCheckingBalance && _currentAutoBuyMpesaTransaction != null) {
          final String? extractedPhoneNumber =
              _currentAutoBuyMpesaTransaction?['extractedPhoneNumber'];
          // ignore: unused_local_variable
          final double? extractedAmount =
              _currentAutoBuyMpesaTransaction?['extractedAmount'];
          // ignore: unused_local_variable
          final String? extractedName =
              _currentAutoBuyMpesaTransaction?['extractedName'];

          if (extractedPhoneNumber != null) {}

          _currentAutoBuyMpesaTransaction = null;
        }

        if (_isCheckingBalance && mounted) {
          setState(() {
            _airtimeBalance = 'Check Failed';
            _isCheckingBalance = false;
          });
          _balanceCheckTimeoutTimer?.cancel();
        }
      },
    );

    _ussdErrorSubscription = PlatformChannels.ussdErrorStream.listen(
      (error) {
        final errorString = error.toString().toLowerCase();
        _failureKeywords.any((k) => errorString.contains(k));
        _showSnackbar('USSD Error: $error', isError: true);

        if (!_isCheckingBalance && _currentAutoBuyMpesaTransaction != null) {
          final String? extractedPhoneNumber =
              _currentAutoBuyMpesaTransaction?['extractedPhoneNumber'];
          // ignore: unused_local_variable
          final double? extractedAmount =
              _currentAutoBuyMpesaTransaction?['extractedAmount'];
          // ignore: unused_local_variable
          final String? extractedName =
              _currentAutoBuyMpesaTransaction?['extractedName'];

          if (extractedPhoneNumber != null) {}

          _currentAutoBuyMpesaTransaction = null;
        }

        if (_isCheckingBalance && mounted) {
          setState(() {
            _airtimeBalance = 'Check Failed';
            _isCheckingBalance = false;
          });
          _balanceCheckTimeoutTimer?.cancel();
        }
      },
      onError: (error) {
        _showSnackbar('USSD Error Stream Error: $error', isError: true);
      },
    );
  }

  void _processReceivedSms(String sender, String body) {
    if (_isCheckingBalance) {
      final normalizedBody = body.toLowerCase();

      final airtimeBalanceRegex = RegExp(
        r'airtime bal:?\s*([\d,]+\.\d{2})\s*ksh',
        caseSensitive: false,
      );
      final balanceMatch = airtimeBalanceRegex.firstMatch(normalizedBody);

      if (balanceMatch != null) {
        String balance = balanceMatch.group(1)!;
        balance = balance.replaceAll(',', '');

        setState(() {
          _airtimeBalance = 'Ksh ${double.parse(balance).toStringAsFixed(2)}';
          _isCheckingBalance = false;
        });
        _balanceCheckTimeoutTimer?.cancel();
      }
    }
  }

  // In _storeTransaction method
  Future<void> _storeTransaction(
    String name,
    double amount,
    String phoneNumber,
    bool isSuccess,
  ) async {
    final transaction = Transactions(
      name: name,
      amount: amount,
      phoneNumber: phoneNumber,
      timestamp: DateTime.now(),
      isSuccess: isSuccess,
    );

    await _dbHelper.insertTransaction(transaction);
  }

  Future<void> _triggerUssdAndNotify(
    String ussdCode,
    int? simSubscriptionId, {
    String? planName,
    String? targetNumber,
  }) async {

    if (simSubscriptionId == null) {
      _showSnackbar(
        'No SIM card selected. Please select a SIM via the SIM icon to trigger USSD.',
        isError: true,
      );
      _currentAutoBuyMpesaTransaction = null;
      return;
    }

    if (!await Permission.phone.isGranted) {
      _showSnackbar(
        'Phone permission not granted. Cannot trigger USSD.',
        isError: true,
      );
      _currentAutoBuyMpesaTransaction = null;
      return;
    }

    // Check if user has sufficient tokens before triggering USSD
    final currentBalance = await UserManager.getCachedTokenBalance() ?? 0;
    if (currentBalance <= 0) {
      final userId = UserManager.getCurrentUserId();
      if (mounted && userId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Insufficient tokens. Please buy more tokens.'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Buy Tokens',
              textColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) =>
                            PaymentScreen(userId: userId, customerName: ''),
                  ),
                );
              },
            ),
          ),
        );
      }
      _currentAutoBuyMpesaTransaction = null;
      return;
    }

    try {
      await PlatformChannels.ussdChannel.invokeMethod('triggerUssd', {
        'ussdCode': ussdCode,
        'simSubscriptionId': simSubscriptionId,
        'transaction': _currentAutoBuyMpesaTransaction,
      });

      // Show that USSD was triggered successfully, but don't deduct tokens yet
      _showSnackbar(
        'USSD triggered successfully! Processing... ⏳',
        isError: false,
      );
    } on PlatformException catch (e) {
      setState(() {
        if (_isCheckingBalance) {
          _airtimeBalance = 'Check Failed';
          _isCheckingBalance = false;
        }
      });
      _balanceCheckTimeoutTimer?.cancel();
      _showSnackbar('Failed to trigger USSD: ${e.message}', isError: true);
      debugPrint('Platform Exception during USSD trigger: $e');
      _currentAutoBuyMpesaTransaction = null;
    } catch (e) {
      setState(() {
        _airtimeBalance = 'Check Failed';
        _isCheckingBalance = false;
      });
      _balanceCheckTimeoutTimer?.cancel();
      _showSnackbar(
        'An unexpected error occurred while triggering USSD.',
        isError: true,
      );
      debugPrint('Unexpected error during USSD trigger: $e');
      _currentAutoBuyMpesaTransaction = null;
    }
  }

  void _setupUssdResponseListener() {
    PlatformChannels.ussdChannel.setMethodCallHandler((call) async {
      if (call.method == 'onUssdResponse') {
        final Map<String, dynamic> response = Map<String, dynamic>.from(
          call.arguments,
        );
        final bool isSuccess = response['isSuccess'] ?? false;
        final bool isFailure = response['isFailure'] ?? false;

        if (isSuccess) {
          // USSD was successful - now deduct the token
          final bool tokenDeducted = await _deductTokenForUssd();
          if (tokenDeducted) {
            if (mounted) {
              _showSnackbar(
                'USSD successful! Token deducted. Bundle activated! 🎉',
                isError: false,
              );
            }
          } else {
            if (mounted) {
              _showSnackbar(
                'USSD successful but token deduction failed. Please contact support. ⚠️',
                isError: true,
              );
            }
          }
        } else if (isFailure) {
          // USSD failed - don't deduct tokens, just inform user
          if (mounted) {
            _showSnackbar(
              'USSD operation failed. No tokens were deducted. ❌',
              isError: true,
            );
          }
        }
      } else if (call.method == 'onUssdError') {
        // USSD error - don't deduct tokens
        if (mounted) {
          _showSnackbar(
            'USSD operation failed. No tokens were deducted. ❌',
            isError: true,
          );
        }
      }
    });
  }

  Future<void> _checkAirtimeBalance() async {
    if (_selectedSimSubscriptionId == null) {
      _showSnackbar(
        'Please select a SIM card first to check balance.',
        isError: true,
      );
      return;
    }

    if (!await Permission.phone.isGranted || !await Permission.sms.isGranted) {
      _showSnackbar(
        'Phone and SMS permissions are required to check balance.',
        isError: true,
      );
      _requestPermissions();
      return;
    }

    _balanceCheckTimeoutTimer?.cancel();
    setState(() {
      _isCheckingBalance = true;
      _airtimeBalance = 'Checking...';
    });

    _balanceCheckTimeoutTimer = Timer(const Duration(seconds: 60), () {
      if (_isCheckingBalance && mounted) {
        setState(() {
          _airtimeBalance = 'Check Failed';
          _isCheckingBalance = false;
        });
      }
    });

    try {
      await PlatformChannels.ussdChannel.invokeMethod('triggerUssd', {
        'ussdCode': '*144#',
        'simSubscriptionId': _selectedSimSubscriptionId,
      });
    } on PlatformException {
      setState(() {
        _airtimeBalance = 'Check Failed';
        _isCheckingBalance = false;
      });
      _balanceCheckTimeoutTimer?.cancel();
    } catch (e) {
      setState(() {
        _airtimeBalance = 'Check Failed';
        _isCheckingBalance = false;
      });
      _balanceCheckTimeoutTimer?.cancel();
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        ),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _setupMidnightClearTimer() {
    _midnightClearTimer?.cancel();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final durationUntilMidnight = midnight.difference(now);

    _midnightClearTimer = Timer(durationUntilMidnight, () async {
      await _clearTransactions();
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await _prefsHelper.setLastClearDate(todayStr);
      _setupMidnightClearTimer(); // Reset for next day
    });
  }

  // Update this method
  Future<void> _clearTransactions() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startTimestamp = startOfToday.millisecondsSinceEpoch;

    await _dbHelper.deleteMessagesBefore(startTimestamp);
    // NEW: Clear transactions
    await _dbHelper.clearTransactions();

    // NEW: Reset in-memory lists
    setState(() {
      _successfulTransactions.clear();
      _failedTransactions.clear();
    });
    await _loadFilteredTransactions();

    if (mounted) {
      _showSnackbar('Transactions cleared for new day');
    }
  }

  // COMPLETE RETRY METHOD

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Compute display balance based on visibility state
    String displayBalance = _airtimeBalance;
    if (!_isBalanceVisible) {
      if (_airtimeBalance.startsWith('Ksh') ||
          RegExp(r'\d').hasMatch(_airtimeBalance)) {
        displayBalance = '******';
      }
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(100),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [madderRed, madderRed.withOpacity(0.8)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            boxShadow: [
              BoxShadow(
                color: madderRed.withOpacity(0.3),
                blurRadius: 15,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left spacer to center the title
                  SizedBox(width: 96), // Width of two icons + spacing
                  // Title with glassmorphism effect
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      child: Text(
                        'Bingwa Sokoni',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: snowWhite,
                          letterSpacing: -0.5,
                          shadows: [
                            Shadow(
                              color: Colors.black.withOpacity(0.3),
                              offset: Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Action buttons with glassmorphism effect
                  Row(
                    children: [
                      Container(
                        margin: EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: IconButton(
                          icon: Icon(Icons.sim_card),
                          tooltip: 'Select SIM for USSD',
                          onPressed: _showSimSelectionDialog,
                          color: Colors.white,
                          iconSize: 22,
                          padding: EdgeInsets.all(8),
                          constraints: BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                      ),
                      Container(
                        margin: EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: IconButton(
                          icon: Icon(Icons.settings),
                          tooltip: 'Settings',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SettingsPage(),
                              ),
                            );
                          },
                          color: Colors.white,
                          iconSize: 22,
                          padding: EdgeInsets.all(8),
                          constraints: BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: snowWhite,
        onRefresh: () async {
          await _loadFilteredTransactions();
          await _loadStoredTransactions(); // NEW: Refresh transactions
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        madderRed.withOpacity(0.9),
                        madderRed.withOpacity(0.7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: madderRed.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Added refresh button here
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Airtime Balance',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black26,
                                    offset: Offset(1, 1),
                                    blurRadius: 3,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!_isCheckingBalance)
                              IconButton(
                                icon: Icon(Icons.refresh, color: Colors.white),
                                onPressed: _checkAirtimeBalance,
                                iconSize: 20,
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 400),
                              transitionBuilder: (
                                Widget child,
                                Animation<double> animation,
                              ) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: animation,
                                    child: child,
                                  ),
                                );
                              },
                              child: Text(
                                displayBalance, // Use computed display balance
                                key: ValueKey<String>(displayBalance),
                                style: GoogleFonts.poppins(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black26,
                                      offset: Offset(1, 1),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _isCheckingBalance
                                ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                                : GestureDetector(
                                  // Added GestureDetector for eye icon
                                  onTap: () {
                                    setState(() {
                                      _isBalanceVisible = !_isBalanceVisible;
                                    });
                                  },
                                  child: Icon(
                                    _isBalanceVisible
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Tokens Card Section
                // Replace the existing buy tokens section with this enhanced card design
                const SizedBox(height: 25),

                // Tokens Card Section
                Container(
                  decoration: BoxDecoration(
                    color: snowWhite,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: madderRed.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Available Tokens',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: madderRed,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: madderRed.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Active',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: madderRed,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Tokens Display Section
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                madderRed.withOpacity(0.05),
                                madderRed.withOpacity(0.1),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: madderRed.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Token Icon
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: madderRed.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.token,
                                  color: madderRed,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),

                              // Token Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Current Balance',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    FutureBuilder<int?>(
                                      future:
                                          UserManager.getCachedTokenBalance(),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState ==
                                            ConnectionState.waiting) {
                                          return Text(
                                            '... Tokens',
                                            style: GoogleFonts.poppins(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: madderRed,
                                            ),
                                          );
                                        }

                                        final tokens = snapshot.data ?? 0;
                                        return AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 400,
                                          ),
                                          transitionBuilder: (
                                            Widget child,
                                            Animation<double> animation,
                                          ) {
                                            return FadeTransition(
                                              opacity: animation,
                                              child: ScaleTransition(
                                                scale: animation,
                                                child: child,
                                              ),
                                            );
                                          },
                                          child: Text(
                                            '$tokens Tokens',
                                            key: ValueKey<int>(tokens),
                                            style: GoogleFonts.poppins(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  tokens > 0
                                                      ? madderRed
                                                      : Colors.grey.shade500,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 4),
                                    FutureBuilder<bool>(
                                      future: UserManager.isUserRegistered(),
                                      builder: (context, snapshot) {
                                        final isRegistered =
                                            snapshot.data ?? false;
                                        return Text(
                                          isRegistered
                                              ? 'Synced with server'
                                              : 'Syncing...',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            color:
                                                isRegistered
                                                    ? Colors.green.shade600
                                                    : Colors.orange.shade600,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),

                              // Refresh Button
                              IconButton(
                                icon: Icon(
                                  _isRefreshingTokens
                                      ? Icons.hourglass_empty
                                      : Icons.refresh,
                                ),
                                onPressed:
                                    _isRefreshingTokens
                                        ? null
                                        : _refreshTokenBalance,
                                color: madderRed.withOpacity(0.7),
                                tooltip: 'Refresh token balance',
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Buy Tokens Button
                        Container(
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [madderRed, madderRed.withOpacity(0.8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: madderRed.withOpacity(0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                // Pass the userId from the widget to the PaymentScreen
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => PaymentScreen(
                                          userId: widget.userId,
                                          customerName: '',
                                        ),
                                  ),
                                ).then((result) {
                                  // If result contains purchased tokens info
                                  if (result != null &&
                                      result['tokensAdded'] != null) {
                                    _addTokensAfterPurchase(
                                      result['tokensAdded'],
                                    );
                                  } else {
                                    // Always refresh token balance when returning from payment screen
                                    _refreshTokenBalance();
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_circle_outline,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Buy Tokens',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Quick Actions Row
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                    width: 1,
                                  ),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      // Add token history logic here
                                    },
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.history,
                                          color: Colors.grey.shade600,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'History',
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                    width: 1,
                                  ),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      // Add transfer tokens logic here
                                    },
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.send,
                                          color: Colors.grey.shade600,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Transfer',
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 25),
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'RECEIVED TRANSACTIONS',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                          letterSpacing: 1.1,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AllTransactionsPage(),
                            ),
                          );
                        },
                        child: Text(
                          'See All',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: madderRed.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _filteredTransactions.isEmpty
                    ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 50),
                      child: Center(
                        child: Text(
                          'No M-Pesa transactions found yet that meet the criteria.',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                    : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _filteredTransactions.length,
                      itemBuilder: (context, index) {
                        final transaction = _filteredTransactions[index];

                        final String extractedName =
                            transaction['extractedName'] ?? 'Unknown Sender';
                        final double? amount = transaction['extractedAmount'];
                        final String phoneNumberDisplay =
                            transaction['extractedPhoneNumber'] ?? '';

                        final String amountDisplay =
                            amount != null
                                ? 'Ksh${amount.toStringAsFixed(2)}'
                                : '';

                        final DateTime messageDateTime =
                            DateTime.fromMillisecondsSinceEpoch(
                              transaction['timestamp'],
                            ).toLocal();

                        final DateTime now = DateTime.now();
                        final String transactionTime;
                        if (messageDateTime.year == now.year &&
                            messageDateTime.month == now.month &&
                            messageDateTime.day == now.day) {
                          transactionTime = DateFormat(
                            'h:mm a',
                          ).format(messageDateTime);
                        } else {
                          transactionTime = DateFormat(
                            'd/M/yy h:mm a',
                          ).format(messageDateTime);
                        }

                        return AnimatedContainer(
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          margin: EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 4,
                          ),
                          decoration: BoxDecoration(
                            color: snowWhite,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: madderRed.withOpacity(0.1),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              splashColor: colorScheme.primary.withOpacity(
                                0.15,
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => TransactionDetailPage(
                                          transaction: transaction,
                                        ),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 20,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            extractedName,
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: madderRed.withOpacity(0.8),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '+ $amountDisplay',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          phoneNumberDisplay,
                                          style: GoogleFonts.poppins(
                                            fontSize: 9,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        Text(
                                          transactionTime,
                                          style: GoogleFonts.poppins(
                                            fontSize: 9,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
              ],
            ),
          ),
        ),
      ),
      backgroundColor: snowWhite,
    );
  }
}
