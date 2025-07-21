// lib/services/shared_preferences_helper.dart
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesHelper {
  static const String _selectedSimIdKey = 'selectedSimSubscriptionId';

  Future<void> saveSelectedSimId(int subscriptionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_selectedSimIdKey, subscriptionId);
  }

  Future<int?> getSelectedSimId() async {
    final prefs = await SharedPreferences.getInstance();
    final int? simId = prefs.getInt(_selectedSimIdKey);
    return simId;
  }

  Future<void> clearSelectedSimId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedSimIdKey);
  }

  Future<void> setLastClearDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastClearDate', date);
  }

  Future<String?> getLastClearDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('lastClearDate');
  }
}
