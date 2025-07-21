// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:newton/models/ussd_data_plan.dart';
import 'package:newton/platform_channels.dart';
import 'package:newton/services/database_helper.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class ManualUssdTriggerPage extends StatefulWidget {
  const ManualUssdTriggerPage({super.key});

  @override
  State<ManualUssdTriggerPage> createState() => _ManualUssdTriggerPageState();
}

class _ManualUssdTriggerPageState extends State<ManualUssdTriggerPage>
    with TickerProviderStateMixin {
  static const MethodChannel _ussdChannel = MethodChannel(
    'com.example.newton/ussd',
  );
  static const MethodChannel _simChannel = MethodChannel(
    'com.example.newton/sim',
  );
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<UssdDataPlan> _dataPlans = [];
  // ignore: unused_field
  List<Map<String, dynamic>> _simCards = []; // Changed from Object to dynamic
  Map<String, dynamic>? _selectedSim;
  UssdDataPlan? _selectedPlan;
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;
  bool _isExecuting = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  static const Color snowWhite = Color(0xFFFCF7F8);
  static const Color madderRed = Color(0xFFA31621);

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadInitialData();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
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

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // FIXED: Add missing snackbar helper methods
  void _showSuccessSnackBar(String message) {
    _showSnackBar(message, Colors.green, Icons.check_circle);
  }

  void _showErrorSnackBar(String message) {
    _showSnackBar(message, Colors.red, Icons.error);
  }

  void _showSnackBar(String message, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // NEW: Function to show SIM selection dialog
  Future<void> _showSimSelectionDialog() async {
    if (await Permission.phone.isGranted) {
      List<Map<String, dynamic>> simCards = [];
      try {
        simCards = await PlatformChannels.getSimCards();
      } on PlatformException catch (e) {
        _showErrorSnackBar("Failed to retrieve SIMs: ${e.message}");
        return;
      }

      if (simCards.isEmpty) {
        _showErrorSnackBar('No active SIM cards found');
        return;
      }

      // Show dialog similar to HomePage
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
                              child: const Icon(
                                Icons.sim_card_rounded,
                                color: Colors.white,
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

                      // SIM Cards List
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: simCards.length,
                          separatorBuilder:
                              (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final sim = simCards[index];
                            final isSelected =
                                _selectedSim != null &&
                                _selectedSim!['subscriptionId'] ==
                                    sim['subscriptionId'];

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  setDialogState(() {});
                                  setState(() {
                                    _selectedSim = {
                                      'subscriptionId': sim['subscriptionId'],
                                      'displayName': sim['displayName'],
                                      'simSlotIndex': sim['simSlotIndex'],
                                    };
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color:
                                        isSelected
                                            ? snowWhite.withOpacity(0.1)
                                            : snowWhite,
                                    border: Border.all(
                                      color:
                                          isSelected
                                              ? madderRed
                                              : madderRed.withOpacity(0.3),
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color:
                                              isSelected
                                                  ? madderRed
                                                  : madderRed.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.sim_card_outlined,
                                          size: 20,
                                          color:
                                              isSelected
                                                  ? Colors.white
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
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
                                              style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.w600,
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
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: madderRed.withOpacity(
                                                  0.6,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: madderRed,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.check,
                                            size: 16,
                                            color: snowWhite,
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

                      // Actions
                      Container(
                        padding: const EdgeInsets.all(24),
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
                                onPressed:
                                    () => Navigator.pop(
                                      dialogContext,
                                    ), // Moved to correct position
                                child: Text(
                                  'Cancel',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    color: madderRed.withOpacity(0.7),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(
                              width: 16,
                            ), // Fixed extra closing parenthesis
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: madderRed,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () {
                                  if (_selectedSim != null) {
                                    Navigator.pop(dialogContext);
                                    _showSuccessSnackBar(
                                      'SIM selected: ${_selectedSim!['displayName']}',
                                    );
                                  } else {
                                    _showErrorSnackBar(
                                      'Please select a SIM card',
                                    );
                                  }
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Confirm Selection',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
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
    } else {
      _showErrorSnackBar('Phone permission required to select SIM');
    }
  }

  // NEW: Widget to display selected SIM card
  Widget _buildSelectedSimCard() {
    if (_selectedSim == null) {
      return Container();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.sim_card, color: madderRed),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (_selectedSim!['displayName'] as String?) ?? 'Selected SIM',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              Text(
                'Slot ${(_selectedSim!['simSlotIndex'] ?? 0) + 1}',
                style: GoogleFonts.poppins(color: Colors.grey.shade600),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _showSimSelectionDialog,
            tooltip: 'Change SIM',
          ),
        ],
      ),
    );
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    try {
      final plans = await _dbHelper.getUssdDataPlans();
      final sims = await _simChannel.invokeMethod('getSimCards');

      setState(() {
        _dataPlans = plans;
        _simCards = List<Map<String, dynamic>>.from(sims);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _executeUssdSequence() async {
    if (_selectedPlan == null || _selectedSim == null) {
      _showErrorSnackBar('Please select a plan and SIM card');
      return;
    }

    if (_phoneController.text.trim().isEmpty) {
      _showErrorSnackBar('Please enter a phone number');
      return;
    }

    setState(() => _isExecuting = true);
    _pulseController.repeat(reverse: true);

    try {
      String ussdCode = _selectedPlan!.ussdCodeTemplate.replaceAll(
        _selectedPlan!.placeholder,
        _phoneController.text.trim(),
      );

      Map<String, Object> transaction = {
        'extractedName': '',
        'extractedAmount': _selectedPlan!.amount,
        'extractedPhoneNumber': _phoneController.text.trim(),
        'purchasedOffer': _selectedPlan!.planName,
      };

      // FIXED: Cast subscriptionId to int
      final result = await _ussdChannel.invokeMethod('triggerUssd', {
        'ussdCode': ussdCode,
        'simSubscriptionId': _selectedSim!['subscriptionId'] as int,
        'transaction': transaction,
      });

      _showSuccessSnackBar('USSD code executed successfully!');
      _showUssdDialog(ussdCode, result);

      // Clear form after successful execution
      setState(() {
        _selectedPlan = null;
        _selectedSim = null;
      });
      _phoneController.clear();
    } catch (e) {
      _showErrorSnackBar('Failed to execute USSD: $e');
    } finally {
      setState(() => _isExecuting = false);
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  void _showUssdDialog(String ussdCode, String result) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.check_circle, color: madderRed, size: 28),
                const SizedBox(width: 12),
                Text(
                  'USSD Executed',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Code Sent:',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    ussdCode,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Status: $result',
                  style: GoogleFonts.poppins(color: Colors.grey.shade600),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'OK',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) getDisplayText,
    required void Function(T?) onChanged,
    required IconData icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonFormField<T>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.grey.shade600),
          labelStyle: GoogleFonts.poppins(
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.grey.shade800,
        ),
        items:
            items.map((item) {
              return DropdownMenuItem<T>(
                value: item,
                child: Text(getDisplayText(item)),
              );
            }).toList(),
        onChanged: onChanged,
        // Add hint for empty state
        hint:
            items.isEmpty
                ? Text(
                  'No SIM cards found',
                  style: GoogleFonts.poppins(color: Colors.grey),
                )
                : null,
      ),
    );
  }

  Widget _buildPhoneInput() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: 'Phone Number',
          hintText: '0712345678',
          prefixIcon: Icon(Icons.phone, color: Colors.grey.shade600),
          labelStyle: GoogleFonts.poppins(
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
          hintStyle: GoogleFonts.poppins(
            color: Colors.grey.shade500,
            fontSize: 14,
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildExecuteButton() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isExecuting ? _pulseAnimation.value : 1.0,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors:
                    _isExecuting
                        ? [Colors.orange, Colors.orange.shade700]
                        : [madderRed, madderRed.withOpacity(0.8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: (_isExecuting ? Colors.orange : madderRed).withOpacity(
                    0.3,
                  ),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isExecuting ? null : _executeUssdSequence,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child:
                  _isExecuting
                      ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Executing...',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      )
                      : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_arrow, color: Colors.white, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'Execute USSD',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectedPlanPreview() {
    if (_selectedPlan == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [madderRed.withOpacity(0.1), madderRed.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: madderRed.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.preview, color: madderRed, size: 20),
              const SizedBox(width: 8),
              Text(
                'Preview',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: madderRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Plan: ${_selectedPlan!.planName}',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Amount: KSh ${_selectedPlan!.amount.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'USSD Template: ${_selectedPlan!.ussdCodeTemplate}',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          if (_phoneController.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Final Code: ${_selectedPlan!.ussdCodeTemplate.replaceAll(_selectedPlan!.placeholder, _phoneController.text)}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'Manual USSD Trigger',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            fontSize: 24,
            color: Colors.white,
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
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Refresh Data',
              onPressed: _loadInitialData,
            ),
          ),
        ],
      ),
      body:
          _isLoading
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(madderRed),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading data...',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              )
              : FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20.0),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: madderRed.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.play_circle_outline,
                                      color: madderRed,
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
                                          'Execute USSD Manually',
                                          style: GoogleFonts.poppins(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                        Text(
                                          'Trigger data plan purchases manually',
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 32),
                              // Form Section
                              if (_dataPlans.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.orange.shade200,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.warning_amber,
                                        color: Colors.orange.shade700,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'No data plans configured. Please add plans first.',
                                          style: GoogleFonts.poppins(
                                            color: Colors.orange.shade800,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else ...[
                                // Data Plan Dropdown
                                _buildDropdown<UssdDataPlan>(
                                  label: 'Select Data Plan',
                                  value: _selectedPlan,
                                  items: _dataPlans,
                                  getDisplayText:
                                      (plan) =>
                                          '${plan.planName} - KSh ${plan.amount.toStringAsFixed(2)}',
                                  onChanged: (plan) {
                                    setState(() => _selectedPlan = plan);
                                  },
                                  icon: Icons.data_usage,
                                ),
                                const SizedBox(height: 20),
                                // NEW: SIM Selection Button (replaces dropdown)
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: _showSimSelectionDialog,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.sim_card,
                                          color:
                                              _selectedSim == null
                                                  ? Colors.grey.shade600
                                                  : madderRed,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          _selectedSim == null
                                              ? 'Select SIM Card'
                                              : 'Change SIM Card',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color:
                                                _selectedSim == null
                                                    ? Colors.grey.shade600
                                                    : Colors.grey.shade800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // NEW: Display selected SIM card
                                if (_selectedSim != null)
                                  _buildSelectedSimCard(),
                                const SizedBox(height: 20),
                                // Phone Number Input
                                _buildPhoneInput(),
                                // Preview Section
                                _buildSelectedPlanPreview(),
                                const SizedBox(height: 32),
                                // Execute Button
                                _buildExecuteButton(),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Info Section
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.blue.shade200,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.blue.shade700,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'How it works',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '1. Select a configured data plan\n'
                                '2. Choose the SIM card to use\n'
                                '3. Enter the recipient phone number\n'
                                '4. Execute the USSD sequence',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.blue.shade700,
                                  height: 1.5,
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
