// Flutter data model for CachedTransaction and a placeholder LocalDatabaseService for local JSON string array caching
 // We will wire this path to main.dart shortly

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CachedTransaction {
  final String id;
  final String merchantName;
  final String category;
  final double amount;
  final DateTime timestamp;
  final String currencyCode;

  CachedTransaction({
    required this.id,
    required this.merchantName,
    required this.category,
    required this.amount,
    required this.timestamp,
    required this.currencyCode,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'merchantName': merchantName,
      'category': category,
      'amount': amount,
      'timestamp': timestamp.toIso8601String(),
      'currencyCode': currencyCode,
    };
  }

  factory CachedTransaction.fromMap(Map<String, dynamic> map) {
    return CachedTransaction(
      id: map['id'] ?? '',
      merchantName: map['merchantName'] ?? '',
      category: map['category'] ?? '',
      amount: (map['amount'] as num).toDouble(),
      timestamp: DateTime.parse(map['timestamp']),
      currencyCode: map['currencyCode'] ?? 'INR',
    );
  }
}

class LocalDatabaseService {
  static const String _storageKey = 'cached_transactions_key';

  // Structural database instantiation point
  Future<void> initDatabase() async {
    // Ensures shared preferences are warmed up and accessible
    await SharedPreferences.getInstance();
  }

  // Reads the offline transactional data string and converts it back to a List
  Future<List<CachedTransaction>> fetchStoredTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_storageKey);

    if (jsonString == null) {
      return []; // Return empty list if no data is cached yet
    }

    try {
      final List<dynamic> decodedList = jsonDecode(jsonString);
      return decodedList
          .map((item) => CachedTransaction.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print("Error parsing local transaction cache: $e");
      return [];
    }
  }

  // Saves your transactions down into the device string storage
  Future<void> saveTransactionBatch(List<CachedTransaction> items) async {
    final prefs = await SharedPreferences.getInstance();

    // Convert your transaction list into serializable Maps, then to a JSON string
    final List<Map<String, dynamic>> mapList = items.map((item) => item.toMap()).toList();
    final String jsonString = jsonEncode(mapList);

    await prefs.setString(_storageKey, jsonString);
  }
}