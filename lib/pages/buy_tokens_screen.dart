import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class PaymentScreen extends StatefulWidget {
  final String userId;
  final String customerName;

  const PaymentScreen({
    super.key,
    required this.userId,
    required this.customerName,
  });

  @override
  _PaymentScreenState createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with TickerProviderStateMixin {
  String selectedPackage = 'package_100';
  final phoneController = TextEditingController();
  bool isLoading = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  static const Color snowWhite = Color(0xFFFCF7F8);
  static const Color madderRed = Color(0xFFA31621);

  final packages = {
    'package_100': {'amount': 15.0, 'tokens': '50', 'label': '50 Tokens'},
    'package_500': {'amount': 35.0, 'tokens': '150', 'label': '150 Tokens'},
    'package_1000': {'amount': 60.0, 'tokens': '250', 'label': '250 Tokens'},
  };
  String _currentTokenBalance = '0';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _animationController.forward();
    _fetchTokenBalance();
  }

  @override
  void dispose() {
    _animationController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<void> _updateTokenBalance(int tokensToAdd) async {
  final userId = UserManager.getCurrentUserId();
  if (userId == null) {
    debugPrint('❌ User ID not available for token update');
    return;
  }

  // Optimistically update local cache for immediate UI response
  final currentBalance = await UserManager.getCachedTokenBalance() ?? 0;
  final optimisticBalance = currentBalance + tokensToAdd;
  await UserManager.updateCachedTokenBalance(optimisticBalance);
  
  if (mounted) {
    setState(() {}); // Refresh UI immediately
  }

  try {
    final response = await http.post(
      Uri.parse('https://bingwa-sokoni-app.onrender.com/api/users/update_tokens'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode({
        'userId': userId,
        'amount': tokensToAdd,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true && data['newBalance'] != null) {
        // Update local cache with server-confirmed balance
        await UserManager.updateCachedTokenBalance(data['newBalance']);
        debugPrint('✅ Tokens added: $tokensToAdd | New balance: ${data['newBalance']}');
      } else {
        debugPrint('⚠️ Token update succeeded but no balance returned');
      }
    } else {
      // Server error - revert to previous balance
      await UserManager.updateCachedTokenBalance(currentBalance);
      debugPrint('❌ Server error: ${response.statusCode}');
      _showSnackbar('Token update failed. Reverting changes.', isError: true);
    }
  } catch (e) {
    // Network error - revert to previous balance
    await UserManager.updateCachedTokenBalance(currentBalance);
    debugPrint('❌ Network error: $e');
    _showSnackbar('Network error. Reverting token changes.', isError: true);
  } finally {
    if (mounted) {
      setState(() {}); // Final UI update
    }
  }
}

  /// Fetches the current token balance from the backend.
  Future<void> _fetchTokenBalance() async {
    try {
      final url = Uri.parse(
        'https://bingwa-sokoni-app.onrender.com/api/users/${widget.userId}/tokens',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _currentTokenBalance =
              data['tokens'].toString(); // Assuming 'tokens' field from API
        });
      } else {
        _showSnackBar("Failed to fetch token balance.", isError: true);
      }
    } catch (e) {
      print("Error fetching token balance: $e");
      _showSnackBar("Error fetching token balance.", isError: true);
    }
  }

  Future<void> initiatePayment() async {
    final phoneInput = phoneController.text.trim();
    final packageData = packages[selectedPackage];
    final amount = packageData?['amount'];
    final String? tokensToAward = packageData?['tokens'] as String?;

    if (phoneInput.isEmpty || amount == null || tokensToAward == null) {
      _showSnackBar(
        "Please enter a valid phone number and select a package.",
        isError: true,
      );
      return;
    }

    // Format phone number
    String formattedPhone = phoneInput;
    if (formattedPhone.startsWith('0')) {
      formattedPhone = formattedPhone.replaceFirst('0', '254');
    } else if (formattedPhone.startsWith('+')) {
      formattedPhone = formattedPhone.replaceFirst('+', '');
    }

    setState(() => isLoading = true);

    try {
      final url = Uri.parse(
        'https://bingwa-sokoni-app.onrender.com/api/payments/initiate',
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': widget.userId,
          'amount': amount,
          'phoneNumber': formattedPhone,
          'packageId': selectedPackage,
          'customerName': widget.customerName,
        }),
      ).timeout(const Duration(seconds: 30));

      final resData = jsonDecode(response.body);

      if (response.statusCode == 200 && resData['success'] == true) {
        final paymentId = resData['paymentId']; // Get payment ID from response
        
        _showSnackBar(
          "📲 Check your phone and enter M-Pesa PIN to complete payment",
          isError: false,
        );
        
        // Start polling for payment confirmation
        _pollForPaymentConfirmation(paymentId, int.parse(tokensToAward));
      } else {
        _showSnackBar(
          "❌ Payment initiation failed: ${resData['message'] ?? 'Unknown error'}",
          isError: true,
        );
        setState(() => isLoading = false);
      }
    } catch (e) {
      print("Payment error: $e");
      _showSnackBar("⚠️ Error initiating payment", isError: true);
      setState(() => isLoading = false);
    }
  }

  Future<void> _pollForPaymentConfirmation(String paymentId, int tokensToAward) async {
    int attempts = 0;
    const int maxAttempts = 30; // 30 attempts * 10 seconds = 5 minutes
    const Duration interval = Duration(seconds: 10);

    while (attempts < maxAttempts) {
      await Future.delayed(interval);
      attempts++;

      try {
        final status = await _checkPaymentStatus(paymentId);
        
        if (status == 'success') {
          // Payment succeeded - add tokens
          await _updateTokenBalance(tokensToAward);
          _showSnackBar("✅ Payment successful! $tokensToAward tokens added", isError: false);
          break;
        } else if (status == 'failed') {
          // Payment failed
          _showSnackBar("❌ Payment failed. Please try again", isError: true);
          break;
        }
        // Continue polling if status is 'pending'
      } catch (e) {
        print("Polling error: $e");
        if (attempts == maxAttempts) {
          _showSnackBar("⚠️ Payment verification timed out", isError: true);
        }
      }
    }
    
    setState(() => isLoading = false);
  }

  Future<String> _checkPaymentStatus(String paymentId) async {
    final url = Uri.parse(
      'https://bingwa-sokoni-app.onrender.com/api/payments/status/$paymentId',
    );

    final response = await http.get(url).timeout(const Duration(seconds: 10));
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['status'] ?? 'pending'; // 'success', 'failed', or 'pending'
    }
    
    throw Exception('Failed to check payment status');
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: snowWhite,
      appBar: AppBar(
        title: Text(
          'Buy Tokens',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            fontSize: 24,
            color: snowWhite,
          ),
        ),
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [madderRed, madderRed.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.white, Colors.grey.shade50],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: madderRed.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.account_balance_wallet,
                          color: madderRed,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Purchase Tokens',
                              style: GoogleFonts.poppins(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: madderRed,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Hello ${widget.customerName}',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            // Inside your Header Section, e.g., below "Hello ${widget.customerName}"
                            Text(
                              'Current Balance: $_currentTokenBalance Tokens',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: madderRed, // Or a contrasting color
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Package Selection Section
                Text(
                  'Select Package',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),

                // Package Cards
                ...packages.entries.map((entry) {
                  final packageId = entry.key;
                  final packageData = entry.value;
                  final isSelected = selectedPackage == packageId;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? madderRed.withOpacity(0.1)
                                : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? madderRed : Colors.grey.shade200,
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(
                              isSelected ? 0.1 : 0.05,
                            ),
                            blurRadius: isSelected ? 15 : 10,
                            offset: Offset(0, isSelected ? 6 : 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap:
                              () => setState(() => selectedPackage = packageId),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color:
                                        isSelected
                                            ? madderRed
                                            : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: Icon(
                                    Icons.star,
                                    color:
                                        isSelected
                                            ? Colors.white
                                            : Colors.grey.shade600,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        packageData['label'] as String,
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              isSelected
                                                  ? madderRed
                                                  : Colors.grey.shade900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'KES ${packageData['amount']}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color:
                                              isSelected
                                                  ? madderRed
                                                  : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: madderRed,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),

                const SizedBox(height: 32),

                // Phone Number Section
                Text(
                  'Payment Details',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),

                // Phone Number Input
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      hintText: 'e.g., 07XXXXXXXX',
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: madderRed.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.phone, color: madderRed, size: 20),
                      ),
                      labelStyle: GoogleFonts.poppins(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                      hintStyle: GoogleFonts.poppins(
                        color: Colors.grey.shade400,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: madderRed, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Payment Summary
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        madderRed.withOpacity(0.1),
                        madderRed.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: madderRed.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Summary',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: madderRed,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Package:',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            packages[selectedPackage]?['label'] as String,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: madderRed,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Amount:',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            'KES ${packages[selectedPackage]?['amount']}',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: madderRed,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Pay Button
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
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: isLoading ? null : initiatePayment,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child:
                            isLoading
                                ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Processing...',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                )
                                : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.payment,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Pay Now',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Security Note
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.security,
                        color: Colors.grey.shade600,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your payment is secure and encrypted',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
