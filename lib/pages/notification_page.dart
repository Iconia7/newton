// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:newton/models/notification.dart';
import 'package:newton/platform_channels.dart';

class NotificationPage extends StatefulWidget {
  final AppNotification? appNotification;

  const NotificationPage({super.key, this.appNotification});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage>
    with TickerProviderStateMixin {
  late NotificationType _finalNotificationType;
  bool _isLoadingTemplates = true;
  bool _isSmsSent = false;
  bool _isSendingSms = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Controllers for templates and keywords
  late TextEditingController _successMessageController;
  late TextEditingController _failureMessageController;
  late TextEditingController _noOfferMessageController;
  late TextEditingController _alreadyMessageController;
  late TextEditingController _successKeywordController;
  late TextEditingController _failureKeywordController;

  // Template visibility toggles
  bool _showSuccessTemplate = false;
  bool _showFailureTemplate = false;
  bool _showNoOfferTemplate = false;
  bool _showAlreadyTemplate = false;

  // Modern color palette
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color secondaryColor = Color(0xFF8B5CF6);
  static const Color successColor = Color(0xFF10B981);
  static const Color failureColor = Color(0xFFEF4444);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color infoColor = Color(0xFF3B82F6);
  static const Color surfaceColor = Color(0xFFF8FAFC);
  static const Color cardColor = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _setupUssdResponseHandler();
    _loadTemplates();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  void _initializeControllers() {
    _successMessageController = TextEditingController();
    _failureMessageController = TextEditingController();
    _noOfferMessageController = TextEditingController();
    _alreadyMessageController = TextEditingController();
    _successKeywordController = TextEditingController();
    _failureKeywordController = TextEditingController();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoadingTemplates = true);

    final prefs = await SharedPreferences.getInstance();
    try {
      setState(() {
        _successMessageController.text =
            prefs.getString('sms_success') ??
            "Thank you [first_name] for choosing and entrusting Nexora Bingwa Sokoni and purchasing [offer] for [amount]. Have a nice time.";

        _failureMessageController.text =
            prefs.getString('sms_failure') ??
            "Dear [first_name], there was a delay while processing your purchase of [offer] for [amount]. Please wait a little bit for it to be loaded.";

        _noOfferMessageController.text =
            prefs.getString('sms_no_offer') ??
            "Sorry [first_name], the amount [amount] sent does not match any of our offers.\nWhatsapp 0115332870 to get list of our offers.";

        _alreadyMessageController.text =
            prefs.getString('sms_already') ??
            "Hey [first_name], Your number [phone] has already been recommended bingwa bundles today\nReply with\n1. Recommend tomorrow\n2. Recommend to this \"number\" (new)";

        _successKeywordController.text =
            prefs.getString('keyword_success') ??
            'activated,successfully,purchased';

        _failureKeywordController.text =
            prefs.getString('keyword_failure') ??
            'failed,error,already,insufficient';
      });
    } catch (e) {
      debugPrint('Error loading templates: $e');
    } finally {
      setState(() => _isLoadingTemplates = false);
    }
  }

  Future<void> _saveTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setString('sms_success', _successMessageController.text);
      await prefs.setString('sms_failure', _failureMessageController.text);
      await prefs.setString('sms_no_offer', _noOfferMessageController.text);
      await prefs.setString('sms_already', _alreadyMessageController.text);
      await prefs.setString('keyword_success', _successKeywordController.text);
      await prefs.setString('keyword_failure', _failureKeywordController.text);

      await PlatformChannels.serviceControlChannel
          .invokeMethod('updateKeywords', {
            'successKeywords':
                _successKeywordController.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList(),
            'failureKeywords':
                _failureKeywordController.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList(),
          });

      _showSuccessSnackBar('Templates saved successfully!');
    } catch (e) {
      _showErrorSnackBar('Failed to save templates: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: failureColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _setupUssdResponseHandler() {
    PlatformChannels.setUssdResponseHandler((response) {
      if (!mounted) return;

      final isSuccess = response['isSuccess'] == true;
      final isFailure = response['isFailure'] == true;

      setState(() {
        _finalNotificationType =
            isSuccess
                ? NotificationType.success
                : (isFailure
                    ? NotificationType.failure
                    : NotificationType.info);
      });

      if (_finalNotificationType != NotificationType.info) {
        _sendResultSms();
      }
    });
  }

  Future<void> _sendResultSms() async {
    if (_finalNotificationType == NotificationType.info) return;

    setState(() => _isSendingSms = true);
    try {
      final phone =
          widget.appNotification?.transactionDetails?['extractedPhoneNumber'];
      if (phone == null || phone.isEmpty) {
        throw Exception('No recipient phone number available');
      }

      final message =
          _finalNotificationType == NotificationType.success
              ? _successMessageController.text
              : _failureMessageController.text;

      final success = await PlatformChannels.sendSms(phone, message);
      setState(() => _isSmsSent = success);

      if (!success) {
        throw Exception('Failed to send SMS');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to send SMS: $e');
    } finally {
      if (mounted) {
        setState(() => _isSendingSms = false);
      }
    }
  }

  Widget _buildModernCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildTemplateSection({
    required String title,
    required TextEditingController controller,
    required IconData icon,
    required Color color,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: _buildModernCard(
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          color: textSecondary,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 20),
                    TextField(
                      controller: controller,
                      maxLines: 6,
                      minLines: 3,
                      style: const TextStyle(
                        fontSize: 16,
                        color: textPrimary,
                        height: 1.5,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter your $title template...',
                        hintStyle: TextStyle(
                          color: textSecondary.withOpacity(0.6),
                          fontSize: 16,
                        ),
                        filled: true,
                        fillColor: surfaceColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: color, width: 2),
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
              ),
              crossFadeState:
                  isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeywordField(
    String label,
    TextEditingController controller,
    Color color,
  ) {
    return _buildModernCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.key, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(fontSize: 16, color: textPrimary),
              decoration: InputDecoration(
                hintText: 'Enter keywords separated by commas...',
                hintStyle: TextStyle(
                  color: textSecondary.withOpacity(0.6),
                  fontSize: 16,
                ),
                filled: true,
                fillColor: surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: color, width: 2),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryColor, secondaryColor],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _saveTemplates,
          borderRadius: BorderRadius.circular(16),
          child: const Center(
            child: Text(
              'SAVE ALL TEMPLATES',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    return _buildModernCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: infoColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt, color: infoColor, size: 24),
                ),
                const SizedBox(width: 16),
                const Text(
                  'Transaction Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildTransactionRow(
              'Phone Number',
              transaction['extractedPhoneNumber'] ?? 'N/A',
              Icons.phone,
            ),
            _buildTransactionRow(
              'Amount',
              transaction['extractedAmount'] ?? 'N/A',
              Icons.attach_money,
            ),
            _buildTransactionRow(
              'Customer Name',
              transaction['extractedName'] ?? 'N/A',
              Icons.person,
            ),
            if (_isSendingSms) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: warningColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(warningColor),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Sending SMS...',
                      style: TextStyle(
                        color: warningColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_isSmsSent) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: successColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: successColor, size: 20),
                    SizedBox(width: 12),
                    Text(
                      'Message sent successfully',
                      style: TextStyle(
                        color: successColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    color: textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transaction = widget.appNotification?.transactionDetails;

    return Scaffold(
      backgroundColor: surfaceColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Message Templates',
          style: TextStyle(
            color: textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: textPrimary),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.save, color: primaryColor),
              ),
              onPressed: _saveTemplates,
            ),
          ),
        ],
      ),
      body:
          _isLoadingTemplates
              ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
              )
              : FadeTransition(
                opacity: _fadeAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSectionTitle('Message Templates'),
                      const SizedBox(height: 16),
                      _buildTemplateSection(
                        title: 'Success Message',
                        controller: _successMessageController,
                        icon: Icons.check_circle_outline,
                        color: successColor,
                        isExpanded: _showSuccessTemplate,
                        onToggle:
                            () => setState(
                              () =>
                                  _showSuccessTemplate = !_showSuccessTemplate,
                            ),
                      ),
                      const SizedBox(height: 16),
                      _buildTemplateSection(
                        title: 'Failure Message',
                        controller: _failureMessageController,
                        icon: Icons.error_outline,
                        color: failureColor,
                        isExpanded: _showFailureTemplate,
                        onToggle:
                            () => setState(
                              () =>
                                  _showFailureTemplate = !_showFailureTemplate,
                            ),
                      ),
                      const SizedBox(height: 16),
                      _buildTemplateSection(
                        title: 'No Offer Message',
                        controller: _noOfferMessageController,
                        icon: Icons.warning_amber_outlined,
                        color: warningColor,
                        isExpanded: _showNoOfferTemplate,
                        onToggle:
                            () => setState(
                              () =>
                                  _showNoOfferTemplate = !_showNoOfferTemplate,
                            ),
                      ),
                      const SizedBox(height: 16),
                      _buildTemplateSection(
                        title: 'Already Recommended',
                        controller: _alreadyMessageController,
                        icon: Icons.repeat_outlined,
                        color: infoColor,
                        isExpanded: _showAlreadyTemplate,
                        onToggle:
                            () => setState(
                              () =>
                                  _showAlreadyTemplate = !_showAlreadyTemplate,
                            ),
                      ),
                      const SizedBox(height: 40),
                      _buildSectionTitle('Response Keywords'),
                      const SizedBox(height: 16),
                      _buildKeywordField(
                        'Success Keywords',
                        _successKeywordController,
                        successColor,
                      ),
                      const SizedBox(height: 16),
                      _buildKeywordField(
                        'Failure Keywords',
                        _failureKeywordController,
                        failureColor,
                      ),
                      const SizedBox(height: 32),
                      _buildSaveButton(),
                      const SizedBox(height: 32),
                      if (transaction != null) ...[
                        _buildSectionTitle('Current Transaction'),
                        const SizedBox(height: 16),
                        _buildTransactionCard(transaction),
                      ],
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _successMessageController.dispose();
    _failureMessageController.dispose();
    _noOfferMessageController.dispose();
    _alreadyMessageController.dispose();
    _successKeywordController.dispose();
    _failureKeywordController.dispose();
    super.dispose();
  }
}
