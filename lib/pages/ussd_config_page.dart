// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:newton/models/ussd_data_plan.dart';
import 'package:newton/services/database_helper.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/services.dart';

class UssdConfigPage extends StatefulWidget {
  const UssdConfigPage({super.key});

  @override
  State<UssdConfigPage> createState() => _UssdConfigPageState();
}

class _UssdConfigPageState extends State<UssdConfigPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<UssdDataPlan> _dataPlans = [];
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _planNameController = TextEditingController();
  final TextEditingController _ussdCodeTemplateController =
      TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _placeholderController = TextEditingController(
    text: 'PN',
  );

  UssdDataPlan? _editingPlan;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  static const Color snowWhite = Color(0xFFFCF7F8);
  static const Color madderRed = Color(0xFFA31621);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

    _loadDataPlans();
    _animationController.forward();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _planNameController.dispose();
    _ussdCodeTemplateController.dispose();
    _amountController.dispose();
    _placeholderController.dispose();
    super.dispose();
  }

  // This listens to lifecycle state changes (app resumed)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      // Check if Accessibility Service is enabled when app returns from background
      bool isEnabled = false;
      try {
        isEnabled = await _isAccessibilityServiceEnabled(
          'com.newton.app/com.newton.accessibility.UssdAccessibilityService',
        );
      } on PlatformException {
        // handle error or set isEnabled = false;
      }

      if (isEnabled) {
        if (mounted) {
          _showModernSnackBar('Accessibility Service enabled!', Colors.green);
        }
      }
    }
  }

  Future<bool> _isAccessibilityServiceEnabled(String serviceId) async {
    // Use platform channel to check if accessibility service is enabled on Android
    const platform = MethodChannel('com.newton.app/accessibility');
    try {
      final bool enabled = await platform.invokeMethod(
        'isAccessibilityServiceEnabled',
        {'serviceId': serviceId},
      );
      return enabled;
    } catch (e) {
      return false;
    }
  }

  Future<void> _loadDataPlans() async {
    final plans = await _dbHelper.getUssdDataPlans();
    setState(() {
      _dataPlans = plans;
    });
  }

  void _clearForm() {
    _planNameController.clear();
    _ussdCodeTemplateController.clear();
    _amountController.clear();
    _placeholderController.text = 'PN';
    _editingPlan = null;
  }

  void _saveDataPlan() async {
    if (_formKey.currentState!.validate()) {
      final newPlan = UssdDataPlan(
        planName: _planNameController.text,
        ussdCodeTemplate: _ussdCodeTemplateController.text,
        amount: double.parse(_amountController.text),
        placeholder: _placeholderController.text,
      );

      if (_editingPlan == null) {
        // Add new plan
        await _dbHelper.insertUssdDataPlan(newPlan);
        _showModernSnackBar('Data Plan added successfully!', Colors.green);
      } else {
        // Update existing plan
        newPlan.id = _editingPlan!.id;
        await _dbHelper.updateUssdDataPlan(newPlan);
        _showModernSnackBar('Data Plan updated successfully!', Colors.blue);
      }
      _loadDataPlans();
      _clearForm();
    }
  }

  void _editPlan(UssdDataPlan plan) {
    setState(() {
      _editingPlan = plan;
      _planNameController.text = plan.planName;
      _ussdCodeTemplateController.text = plan.ussdCodeTemplate;
      _amountController.text = plan.amount.toString();
      _placeholderController.text = plan.placeholder;
    });
  }

  void _deletePlan(int id) async {
    await _dbHelper.deleteUssdDataPlan(id);
    _loadDataPlans();
    _showModernSnackBar('Data Plan deleted', Colors.orange);
  }

  void _showModernSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == Colors.green
                  ? Icons.check_circle
                  : color == Colors.blue
                  ? Icons.info
                  : Icons.warning,
              color: Colors.white,
              size: 20,
            ),
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

  void openAccessibilitySettings() {
    final intent = AndroidIntent(
      action: 'android.settings.ACCESSIBILITY_SETTINGS',
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    intent.launch();
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    String? hint,
    TextInputType? keyboardType,
    IconData? prefixIcon,
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
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon:
              prefixIcon != null
                  ? Icon(prefixIcon, color: Colors.grey.shade600)
                  : null,
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
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.red, width: 1),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: snowWhite,
      appBar: AppBar(
        title: Text(
          'Data Plans',
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
              icon: const Icon(Icons.accessibility_new, color: Colors.white),
              tooltip: 'Open Accessibility Settings',
              onPressed: openAccessibilitySettings,
            ),
          ),
        ],
      ),
      body: FadeTransition(
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
                              color: madderRed,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.settings_cell,
                              color: snowWhite,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Configure Data Plans',
                                  style: GoogleFonts.poppins(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                                Text(
                                  'Set up USSD codes and data plans',
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
                      const SizedBox(height: 24),

                      // Form Section
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildModernTextField(
                              controller: _planNameController,
                              label: 'Plan Name',
                              hint: 'e.g., 50MB Daily',
                              prefixIcon: Icons.label_outline,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a plan name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            _buildModernTextField(
                              controller: _ussdCodeTemplateController,
                              label: 'USSD Code Template',
                              hint: '*180*5*2*PN*1*1#',
                              prefixIcon: Icons.code,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a USSD code template';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            _buildModernTextField(
                              controller: _amountController,
                              label: 'Amount (KSh)',
                              hint: '50.0',
                              prefixIcon: Icons.attach_money,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter an amount';
                                }
                                if (double.tryParse(value) == null) {
                                  return 'Please enter a valid number';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            _buildModernTextField(
                              controller: _placeholderController,
                              label: 'Placeholder',
                              hint: 'Will be replaced with extracted data',
                              prefixIcon: Icons.text_fields,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a placeholder';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 32),

                            // Action Buttons
                            Row(
                              children: [
                                if (_editingPlan != null) ...[
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _clearForm,
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        side: BorderSide(
                                          color: Colors.grey.shade400,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Text(
                                        'Cancel',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                ],
                                Expanded(
                                  flex: _editingPlan != null ? 2 : 1,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: LinearGradient(
                                        colors: [
                                          madderRed,
                                          madderRed.withOpacity(0.8),
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: madderRed,
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton(
                                      onPressed: _saveDataPlan,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _editingPlan == null
                                                ? Icons.add
                                                : Icons.update,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _editingPlan == null
                                                ? 'Add Plan'
                                                : 'Update Plan',
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
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Data Plans List Section
                Text(
                  'Configured Plans',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 16),

                _dataPlans.isEmpty
                    ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.inbox_outlined,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Plans Configured',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add your first data plan configuration above',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _dataPlans.length,
                      itemBuilder: (context, index) {
                        final plan = _dataPlans[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
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
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(20),
                            leading: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: madderRed.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.sim_card,
                                color: madderRed,
                                size: 24,
                              ),
                            ),
                            title: Text(
                              plan.planName,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade900,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'KSh ${plan.amount.toStringAsFixed(2)}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  plan.ussdCodeTemplate.replaceAll(
                                    plan.placeholder,
                                    '<Phone Number>',
                                  ),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: madderRed.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.edit_outlined,
                                      color: madderRed,
                                      size: 20,
                                    ),
                                    onPressed: () => _editPlan(plan),
                                    tooltip: 'Edit Plan',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: Colors.red.shade600,
                                      size: 20,
                                    ),
                                    onPressed: () => _deletePlan(plan.id!),
                                    tooltip: 'Delete Plan',
                                  ),
                                ),
                              ],
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
    );
  }
}
