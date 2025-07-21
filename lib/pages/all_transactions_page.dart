// lib/pages/all_transactions_page.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:newton/services/database_helper.dart';
import 'package:intl/intl.dart';

class AllTransactionsPage extends StatefulWidget {
  const AllTransactionsPage({super.key});

  @override
  _AllTransactionsPageState createState() => _AllTransactionsPageState();
}

class _AllTransactionsPageState extends State<AllTransactionsPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _allTransactions = [];
  final DatabaseHelper _dbHelper = DatabaseHelper();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  String _searchQuery = '';
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _loadAllTransactions();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadAllTransactions() async {
    final allMessages = await _dbHelper.getMessages();
    setState(() {
      _allTransactions = allMessages;
    });
    _animationController.forward();
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    if (_searchQuery.isEmpty) return _allTransactions;
    return _allTransactions.where((transaction) {
      final sender = (transaction['sender'] ?? '').toLowerCase();
      final body = (transaction['body'] ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      return sender.contains(query) || body.contains(query);
    }).toList();
  }

  String _getTransactionType(String? body) {
    if (body == null) return 'Unknown';
    body = body.toLowerCase();
    if (body.contains('received') || body.contains('credit')) return 'Credit';
    if (body.contains('sent') || body.contains('debit')) return 'Debit';
    if (body.contains('withdraw')) return 'Withdrawal';
    if (body.contains('deposit')) return 'Deposit';
    return 'Transaction';
  }

  Color _getTransactionColor(String type) {
    switch (type) {
      case 'Credit':
      case 'Deposit':
        return const Color(0xFF00C853);
      case 'Debit':
      case 'Withdrawal':
        return const Color(0xFFFF3D00);
      default:
        return const Color(0xFF2196F3);
    }
  }

  IconData _getTransactionIcon(String type) {
    switch (type) {
      case 'Credit':
      case 'Deposit':
        return Icons.arrow_downward_rounded;
      case 'Debit':
      case 'Withdrawal':
        return Icons.arrow_upward_rounded;
      default:
        return Icons.swap_horiz_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF8FAFC),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            surfaceTintColor: Colors.transparent,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: isDark ? Colors.white : Colors.black87,
                  size: 20,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              title:
                  _isSearching
                      ? Container(
                        height: 40,
                        margin: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          color:
                              isDark
                                  ? const Color(0xFF2A2A2A)
                                  : Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                isDark
                                    ? const Color(0xFF3A3A3A)
                                    : Colors.grey[300]!,
                          ),
                        ),
                        child: TextField(
                          autofocus: true,
                          onChanged:
                              (value) => setState(() => _searchQuery = value),
                          decoration: InputDecoration(
                            hintText: 'Search transactions...',
                            hintStyle: GoogleFonts.inter(
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[600],
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[600],
                              size: 20,
                            ),
                          ),
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      )
                      : Text(
                        'All Transactions',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 28,
                          color: isDark ? Colors.white : Colors.black87,
                          letterSpacing: -0.5,
                        ),
                      ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: Icon(
                    _isSearching ? Icons.close_rounded : Icons.search_rounded,
                    color: isDark ? Colors.white : Colors.black87,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _isSearching = !_isSearching;
                      if (!_isSearching) _searchQuery = '';
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.primaryColor.withOpacity(0.1),
                          theme.primaryColor.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: theme.primaryColor.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.receipt_long_rounded,
                          size: 16,
                          color: theme.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_filteredTransactions.length} transactions',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _filteredTransactions.isEmpty
              ? SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.grey[200]!, Colors.grey[100]!],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(60),
                        ),
                        child: Icon(
                          Icons.receipt_long_rounded,
                          size: 50,
                          color: Colors.grey[400],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _searchQuery.isEmpty
                            ? 'No transactions found'
                            : 'No matches found',
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _searchQuery.isEmpty
                            ? 'Your transactions will appear here'
                            : 'Try adjusting your search terms',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: isDark ? Colors.grey[400] : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              )
              : SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final transaction = _filteredTransactions[index];
                  final DateTime messageDateTime =
                      DateTime.fromMillisecondsSinceEpoch(
                        transaction['timestamp'],
                      ).toLocal();

                  final String transactionTime = DateFormat(
                    'MMM d, yyyy • h:mm a',
                  ).format(messageDateTime);

                  final String transactionType = _getTransactionType(
                    transaction['body'],
                  );
                  final Color transactionColor = _getTransactionColor(
                    transactionType,
                  );
                  final IconData transactionIcon = _getTransactionIcon(
                    transactionType,
                  );

                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color:
                              isDark
                                  ? const Color(0xFF2A2A2A)
                                  : Colors.grey[200]!,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                isDark
                                    ? Colors.black.withOpacity(0.3)
                                    : Colors.black.withOpacity(0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            // Handle transaction tap - could show details
                            _showTransactionDetails(context, transaction);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        transactionColor.withOpacity(0.2),
                                        transactionColor.withOpacity(0.1),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: transactionColor.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Icon(
                                    transactionIcon,
                                    color: transactionColor,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              transaction['sender'] ??
                                                  'Unknown Sender',
                                              style: GoogleFonts.inter(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    isDark
                                                        ? Colors.white
                                                        : Colors.black87,
                                                letterSpacing: -0.3,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  transactionColor.withOpacity(
                                                    0.15,
                                                  ),
                                                  transactionColor.withOpacity(
                                                    0.05,
                                                  ),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: transactionColor
                                                    .withOpacity(0.3),
                                              ),
                                            ),
                                            child: Text(
                                              transactionType,
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: transactionColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        transaction['body'] ?? 'No Message',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          color:
                                              isDark
                                                  ? Colors.grey[300]
                                                  : Colors.grey[600],
                                          height: 1.4,
                                          fontWeight: FontWeight.w400,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time_rounded,
                                            size: 14,
                                            color:
                                                isDark
                                                    ? Colors.grey[400]
                                                    : Colors.grey[500],
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            transactionTime,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color:
                                                  isDark
                                                      ? Colors.grey[400]
                                                      : Colors.grey[500],
                                              fontWeight: FontWeight.w500,
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
                        ),
                      ),
                    ),
                  );
                }, childCount: _filteredTransactions.length),
              ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
        ],
      ),
    );
  }

  void _showTransactionDetails(
    BuildContext context,
    Map<String, dynamic> transaction,
  ) {
    final DateTime messageDateTime =
        DateTime.fromMillisecondsSinceEpoch(transaction['timestamp']).toLocal();

    final String transactionType = _getTransactionType(transaction['body']);
    final Color transactionColor = _getTransactionColor(transactionType);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Transaction Details',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 24),
                _buildDetailRow('Sender', transaction['sender'] ?? 'Unknown'),
                _buildDetailRow(
                  'Type',
                  transactionType,
                  color: transactionColor,
                ),
                _buildDetailRow(
                  'Time',
                  DateFormat('MMM d, yyyy • h:mm:ss a').format(messageDateTime),
                ),
                const SizedBox(height: 16),
                Text(
                  'Message',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Text(
                    transaction['body'] ?? 'No message content',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
