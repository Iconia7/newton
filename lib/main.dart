import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:newton/models/error_screens.dart';
import 'package:newton/models/loading_screens.dart';
import 'package:newton/models/mainwrapper.dart';
import 'package:newton/pages/buy_tokens_screen.dart';
import 'package:newton/platform_channels.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize app components
  await _initializeApp();

  runApp(const MyApp());
}

List<String> successKeywords = [];
List<String> failureKeywords = [];

Future<void> _initializeApp() async {
  // Load keywords from preferences
  await _loadKeywords();

  // Initialize platform channels
  PlatformChannels.initUssdMethodCallHandler();

  // Start background service with initial keywords
  await _startBackgroundService();
}

Future<void> _loadKeywords() async {
  final prefs = await SharedPreferences.getInstance();
  successKeywords =
      prefs.getStringList('successKeywords') ??
      ['success', 'confirmed', 'completed'];
  failureKeywords =
      prefs.getStringList('failureKeywords') ?? ['fail', 'error', 'invalid'];
}

// Method channel for communication with native background service
const MethodChannel _backgroundServiceChannel = MethodChannel(
  'com.example.newton/background_service',
);

Future<void> _startBackgroundService() async {
  try {
    await _backgroundServiceChannel.invokeMethod('startService', {
      'successKeywords': successKeywords,
      'failureKeywords': failureKeywords,
    });
    debugPrint('Background service started');
  } catch (e) {
    debugPrint('Failed to start background service: $e');
  }
}

Future<void> stopBackgroundService() async {
  try {
    await _backgroundServiceChannel.invokeMethod('stopService');
    debugPrint('Background service stopped');
  } catch (e) {
    debugPrint('Failed to stop background service: $e');
  }
}

enum RegistrationStatus { pending, completed, failed }

// Enhanced User Management Class
class UserManager {
  static const String _backendBaseUrl =
      'https://bingwa-sokoni-app.onrender.com';
  static const String _userIdKey = 'anonymousUser Id';
  static const String _registrationStatusKey = 'userRegistrationStatus';
  static const String _lastRegistrationAttemptKey = 'lastRegistrationAttempt';
  static const String _tokenBalanceKey = 'tokenBalance';

  static String? _cachedUserId;

  // Get or create user ID with proper error handling
  static Future<String> getOrCreateUserId() async {
    if (_cachedUserId != null) return _cachedUserId!;

    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString(_userIdKey);

    if (storedId == null) {
      storedId = const Uuid().v4();
      await prefs.setString(_userIdKey, storedId);
      debugPrint('Generated new user ID: $storedId');
    }

    _cachedUserId = storedId;

    // Check if registration is complete, if not, attempt registration
    await _ensureUserRegistration(storedId);

    return storedId;
  }

  // Ensure user is properly registered on backend with retry logic
  static Future<void> _ensureUserRegistration(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final statusStr = prefs.getString(_registrationStatusKey);
    final status = RegistrationStatus.values.firstWhere(
      (e) => e.name == statusStr,
      orElse: () => RegistrationStatus.pending,
    );

    if (status == RegistrationStatus.completed) {
      debugPrint('User already registered on backend');
      return;
    }

    // Check if we should retry (avoid too frequent attempts)
    final lastAttempt = prefs.getInt(_lastRegistrationAttemptKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    const retryDelay = 5 * 60 * 1000; // 5 minutes

    if (status == RegistrationStatus.failed &&
        (now - lastAttempt) < retryDelay) {
      debugPrint('Skipping registration retry (too soon)');
      return;
    }

    await _attemptUserRegistration(userId);
  }

  // Attempt user registration with proper error handling
  static Future<void> _attemptUserRegistration(String userId) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      await prefs.setInt(
        _lastRegistrationAttemptKey,
        DateTime.now().millisecondsSinceEpoch,
      );

      final response = await http
          .post(
            Uri.parse('$_backendBaseUrl/api/users/register_anonymous'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({
              'userId': userId,
              'deviceInfo': await _getDeviceInfo(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          // Registration successful
          await prefs.setString(
            _registrationStatusKey,
            RegistrationStatus.completed.name,
          );

          // Cache initial token balance if provided by backend
          if (data['tokens'] != null) {
            await prefs.setInt(_tokenBalanceKey, data['tokens']);
          }

          debugPrint(
            '✅ User registered successfully with ${data['tokens'] ?? 20} tokens',
          );
        } else {
          // Backend returned error
          await prefs.setString(
            _registrationStatusKey,
            RegistrationStatus.failed.name,
          );
          debugPrint('❌ Backend registration failed: ${data['message']}');
        }
      } else {
        // HTTP error
        await prefs.setString(
          _registrationStatusKey,
          RegistrationStatus.failed.name,
        );
        debugPrint('❌ Registration failed with status: ${response.statusCode}');
      }
    } catch (e) {
      // Network or other error
      await prefs.setString(
        _registrationStatusKey,
        RegistrationStatus.failed.name,
      );
      debugPrint('❌ Registration error: $e');
    }
  }

  // Get basic device info for backend
  static Future<Map<String, dynamic>> _getDeviceInfo() async {
    return {
      'platform': 'android', // or detect dynamically
      'appVersion': '1.0.0',
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // Get current user ID (synchronous, for UI)
  static String? getCurrentUserId() => _cachedUserId;

  // Check if user is properly registered
  static Future<bool> isUserRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    final statusStr = prefs.getString(_registrationStatusKey);
    return statusStr == RegistrationStatus.completed.name;
  }

  // Get cached token balance
  static Future<int?> getCachedTokenBalance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_tokenBalanceKey);
  }

  // Update cached token balance
  static Future<void> updateCachedTokenBalance(int balance) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_tokenBalanceKey, balance);
  }

  // Retry user registration manually
  static Future<void> retryRegistration() async {
    final userId = await getOrCreateUserId();
    await _attemptUserRegistration(userId);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bingwa Sokoni',
      debugShowCheckedModeBanner: false,
      theme: _buildAppTheme(),
      home: FutureBuilder<String>(
        future: UserManager.getOrCreateUserId(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ModernLoadingScreen();
          }
          if (snapshot.hasError) {
            return ModernErrorScreen(
              errorMessage: _getErrorMessage(snapshot.error),
              onRetry: () => _retryInitialization(context),
            );
          }

          final userId = snapshot.data!;
          return AppRouter(userId: userId);
        },
      ),
    );
  }

  ThemeData _buildAppTheme() {
    return ThemeData(
      primarySwatch: Colors.teal,
      colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.teal).copyWith(
        secondary: Colors.cyan,
        tertiary: Colors.amberAccent,
        surface: Colors.grey.shade100,
      ),
      textTheme: TextTheme(
        headlineSmall: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
        titleMedium: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
        titleSmall: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade700,
        ),
        bodySmall: TextStyle(color: Colors.grey.shade600),
        bodyMedium: const TextStyle(color: Colors.black87),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.teal,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.teal),
      ),
    );
  }
}

// Function to handle retry initialization
Future<void> _retryInitialization(BuildContext context) async {
  try {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // Retry user registration
    await UserManager.retryRegistration();

    // Re-initialize app components
    await _initializeApp();

    // Close loading dialog
    if (context.mounted) {
      Navigator.of(context).pop();

      // Restart the app by replacing the current route
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const MyApp()),
        (route) => false,
      );
    }
  } catch (e) {
    // Close loading dialog if still open
    if (context.mounted) {
      Navigator.of(context).pop();

      // Show error snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Retry failed: ${_getErrorMessage(e)}'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Try Again',
            onPressed: () => _retryInitialization(context),
          ),
        ),
      );
    }
  }
}

String _getErrorMessage(dynamic error) {
  if (error.toString().contains('SocketException') ||
      error.toString().contains('TimeoutException')) {
    return 'Unable to connect to server. Please check your internet connection and try again.';
  } else if (error.toString().contains('FormatException')) {
    return 'Server returned invalid data. Please try again later.';
  } else {
    return 'An unexpected error occurred. Please try again.';
  }
}

// Router widget to handle navigation
class AppRouter extends StatelessWidget {
  final String userId;

  const AppRouter({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(
              builder: (context) => MainWrapper(userId: userId),
            );
          case '/buy_tokens':
            return MaterialPageRoute(
              builder: (context) => PaymentScreen(
                userId: userId,
                customerName: '',
              ),
            );
          default:
            return MaterialPageRoute(
              builder: (context) => MainWrapper(userId: userId),
            );
        }
      },
    );
  }
}