import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:universal_html/html.dart' as html;
import 'database_service.dart';
import 'cloud_sync_service.dart';
import 'firestore_service.dart';
import 'firebase_options.dart';
// Needed to convert your list into a JSON string for storage

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await dotenv.load(fileName: ".env");
  runApp(const ProviderScope(child: FinanceApp()));
}

class FinanceApp extends ConsumerWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'SmartLedger AI',
      debugShowCheckedModeBanner: false,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const MainNavigationScreen();
        }
        return const AuthScreen();
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLoading = false;

  Future<void> _submit() async {
    setState(() => isLoading = true);
    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isLogin ? "Welcome Back" : "Create Account",
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 32),
            if (isLoading)
              const CircularProgressIndicator()
            else ...[
              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: Text(isLogin ? "Sign In" : "Sign Up"),
              ),
              TextButton(
                onPressed: () => setState(() => isLogin = !isLogin),
                child: Text(
                  isLogin
                      ? "Don't have an account? Sign Up"
                      : "Already have an account? Sign In",
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- APP SERVICES LAYER (RIVERPOD NOTIFIER) ---

class TransactionNotifier extends Notifier<List<Map<String, dynamic>>> {
  static const String _savedTransactionsKey = 'saved_transactions';
  bool _hasHydrated = false;

  @override
  List<Map<String, dynamic>> build() {
    _loadDataFromLocal();
    return [
      {
        "id": "seed_starbucks_180_today",
        "merchant": "Starbucks Coffee",
        "amount": 180.00,
        "date": "Today",
      },
      {
        "id": "seed_netflix_649_yesterday",
        "merchant": "Netflix Subscription",
        "amount": 649.00,
        "date": "Yesterday",
      },
      {
        "id": "seed_electric_2450_24june",
        "merchant": "Electric Bill",
        "amount": 2450.00,
        "date": "24 June",
      },
      {
        "id": "seed_zomato_420_22june",
        "merchant": "Zomato Delivery",
        "amount": 420.00,
        "date": "22 June",
      },
      {
        "id": "seed_petrol_1000_21june",
        "merchant": "Petrol Pump",
        "amount": 1000.00,
        "date": "21 June",
      },
    ];
  }

  Future<void> hydrateFromLocal() async {
    await _loadDataFromLocal();
  }

  Future<void> persistDataToLocal() async {
    await _saveDataToLocal();
  }

  Future<void> _saveDataToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final preferredCurrency = ref.read(currencyPreferenceProvider);
      final payload = jsonEncode({
        'preferredCurrency': preferredCurrency,
        'transactions': state
            .map(
              (tx) => {
                'merchant': tx['merchant']?.toString() ?? 'Unknown Merchant',
                'amount': (tx['amount'] as num?)?.toDouble() ?? 0.0,
                'date': tx['date']?.toString() ?? DateTime.now().toString(),
                if (tx['category'] != null)
                  'category': tx['category']?.toString(),
              },
            )
            .toList(),
      });

      await prefs.setString(_savedTransactionsKey, payload);
    } catch (e) {
      debugPrint('Save transactions error: $e');
    }
  }

  Future<void> _loadDataFromLocal() async {
    if (_hasHydrated) return;
    _hasHydrated = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_savedTransactionsKey);
      if (raw == null || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      List<dynamic>? decodedTransactions;

      if (decoded is List) {
        decodedTransactions = decoded;
      } else if (decoded is Map<String, dynamic>) {
        final savedCurrency = decoded['preferredCurrency']?.toString();
        if (savedCurrency != null &&
            _supportedCurrencies.contains(savedCurrency)) {
          ref
              .read(currencyPreferenceProvider.notifier)
              .hydrateCurrencyCode(savedCurrency);
        }

        final txList = decoded['transactions'];
        if (txList is List) {
          decodedTransactions = txList;
        }
      }

      if (decodedTransactions == null) return;

      final loaded = <Map<String, dynamic>>[];
      for (final item in decodedTransactions) {
        if (item is! Map) continue;

        final merchant = item['merchant']?.toString() ?? 'Unknown Merchant';
        final amountValue = item['amount'];
        final amount = amountValue is num
            ? amountValue.toDouble()
            : double.tryParse(amountValue?.toString() ?? '0') ?? 0.0;
        final date = item['date']?.toString() ?? DateTime.now().toString();
        final category = item['category']?.toString();

        final id =
            item['id']?.toString() ??
            '${merchant}_${amount.toStringAsFixed(2)}_$date';

        loaded.add({
          'id': id,
          'merchant': merchant,
          'amount': amount,
          'date': date,
          if (category != null && category.isNotEmpty) 'category': category,
        });
      }

      state = loaded;
    } catch (e) {
      debugPrint('Load transactions error: $e');
    }
  }

  void addTransaction(
    String merchant,
    double amount, {
    String? category,
    String? date,
  }) {
    state = [
      {
        "id": _generateId(merchant, amount, date),
        "merchant": merchant,
        "amount": amount,
        "date": date ?? "Just Now",
        if (category != null) "category": category,
      },
      ...state,
    ];

    _saveDataToLocal();
  }

  /// Removes the transaction matching [id] from the state, then triggers
  /// a persist to local cache so the deletion survives an app restart.
  void deleteTransaction(String id) {
    state = state.where((tx) {
      final existingId = tx['id']?.toString();
      return existingId == null || existingId != id;
    }).toList();

    _saveDataToLocal();
  }

  /// Updates an existing transaction (matched by [id]) in place. Used to
  /// keep the list consistent when an item is mutated externally while
  /// still preserving order.
  void updateTransactionCategory(String id, String newCategory) {
    state = state.map((tx) {
      if (tx['id']?.toString() != id) return tx;
      return {...tx, 'category': newCategory};
    }).toList();

    _saveDataToLocal();
  }

  String _generateId(String merchant, double amount, String? date) {
    final stamp = date?.toString() ?? DateTime.now().toIso8601String();
    return '${merchant}_${amount.toStringAsFixed(2)}_$stamp';
  }
}

final transactionProvider =
    NotifierProvider<TransactionNotifier, List<Map<String, dynamic>>>(() {
      return TransactionNotifier();
    });

const Map<String, String> _currencySymbols = {
  'INR': '₹',
  'USD': '\$',
  'EUR': '€',
};

const Map<String, double> _currencyToInrRate = {
  'INR': 1.0,
  'USD': 83.0,
  'EUR': 90.0,
};

const List<String> _supportedCurrencies = ['INR', 'USD', 'EUR'];

class CurrencyPreferenceNotifier extends Notifier<String> {
  static const String _savedCurrencyKey = 'saved_currency_code';
  bool _hasHydrated = false;

  @override
  String build() {
    _loadDataFromLocal();
    return 'INR';
  }

  Future<void> setCurrencyCode(String currencyCode) async {
    if (!_supportedCurrencies.contains(currencyCode)) return;
    state = currencyCode;
    await _saveDataToLocal();
  }

  void hydrateCurrencyCode(String currencyCode) {
    if (!_supportedCurrencies.contains(currencyCode)) return;
    state = currencyCode;
  }

  Future<void> _saveDataToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_savedCurrencyKey, state);
      await ref.read(transactionProvider.notifier).persistDataToLocal();
    } catch (e) {
      debugPrint('Save currency preference error: $e');
    }
  }

  Future<void> _loadDataFromLocal() async {
    if (_hasHydrated) return;
    _hasHydrated = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_savedCurrencyKey);
      if (saved != null && _supportedCurrencies.contains(saved)) {
        state = saved;
      }
    } catch (e) {
      debugPrint('Load currency preference error: $e');
    }
  }
}

final currencyPreferenceProvider =
    NotifierProvider<CurrencyPreferenceNotifier, String>(() {
      return CurrencyPreferenceNotifier();
    });

class ThemeNotifier extends Notifier<bool> {
  static const String _themeKey = 'isDarkMode';

  @override
  bool build() {
    _loadTheme();
    return false;
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_themeKey) ?? false;
  }

  Future<void> toggleTheme(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeKey, value);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, bool>(ThemeNotifier.new);

const Map<String, double> _defaultCategoryBudgets = {
  'Food': 5000.0,
  'Café': 2000.0,
  'Transport': 3000.0,
  'Entertainment': 4000.0,
  'Shopping': 6000.0,
};

const double _defaultMonthlyBudgetCap = 0.0;

class BudgetLimitsNotifier extends Notifier<Map<String, double>> {
  static const String _savedBudgetLimitsKey = 'saved_budget_limits';
  bool _hasHydrated = false;

  @override
  Map<String, double> build() {
    _loadDataFromLocal();
    return Map<String, double>.from(_defaultCategoryBudgets);
  }

  Future<void> updateCategoryLimit(String category, double newLimit) async {
    if (newLimit <= 0) return;

    state = {...state, category: newLimit};

    await _saveDataToLocal();
  }

  Future<void> _saveDataToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_savedBudgetLimitsKey, jsonEncode(state));
      await ref.read(transactionProvider.notifier).persistDataToLocal();
    } catch (e) {
      debugPrint('Save budget limits error: $e');
    }
  }

  Future<void> _loadDataFromLocal() async {
    if (_hasHydrated) return;
    _hasHydrated = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_savedBudgetLimitsKey);
      if (raw == null || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final merged = Map<String, double>.from(_defaultCategoryBudgets);
      decoded.forEach((key, value) {
        final parsedValue = value is num
            ? value.toDouble()
            : double.tryParse(value.toString());
        if (parsedValue != null && parsedValue > 0) {
          merged[key.toString()] = parsedValue;
        }
      });

      state = merged;
    } catch (e) {
      debugPrint('Load budget limits error: $e');
    }
  }
}

final budgetLimitsProvider =
    NotifierProvider<BudgetLimitsNotifier, Map<String, double>>(() {
      return BudgetLimitsNotifier();
    });

class MonthlyBudgetCapNotifier extends Notifier<double> {
  static const String _savedMonthlyBudgetCapKey = 'saved_monthly_budget_cap';
  bool _hasHydrated = false;
  final FirestoreService _firestoreService = FirestoreService();

  @override
  double build() {
    _loadDataFromLocal();
    _listenToFirestore();
    return _defaultMonthlyBudgetCap;
  }

  void _listenToFirestore() {
    _firestoreService.getMonthlyIncomeStream().listen((income) {
      if (income != null && income > 0) {
        state = income;
        _saveToLocalOnly(income);
      }
    });
  }

  Future<void> updateBudgetCap(double newCap) async {
    if (newCap <= 0) return;
    state = newCap;
    await _saveDataToLocal();
    await _firestoreService.updateMonthlyIncome(newCap);
  }

  Future<void> _saveToLocalOnly(double cap) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_savedMonthlyBudgetCapKey, cap);
    } catch (e) {
      debugPrint('Save local cap error: $e');
    }
  }

  Future<void> _saveDataToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_savedMonthlyBudgetCapKey, state);
      await ref.read(transactionProvider.notifier).persistDataToLocal();
    } catch (e) {
      debugPrint('Save monthly budget cap error: $e');
    }
  }

  Future<void> _loadDataFromLocal() async {
    if (_hasHydrated) return;
    _hasHydrated = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_savedMonthlyBudgetCapKey);
      if (saved != null && saved > 0) {
        state = saved;
      }
    } catch (e) {
      debugPrint('Load monthly budget cap error: $e');
    }
  }
}

final monthlyBudgetCapProvider =
    NotifierProvider<MonthlyBudgetCapNotifier, double>(() {
      return MonthlyBudgetCapNotifier();
    });

class BankBalanceNotifier extends Notifier<double> {
  static const String _savedBankBalanceKey = 'saved_bank_balance';
  bool _hasHydrated = false;
  final FirestoreService _firestoreService = FirestoreService();

  @override
  double build() {
    _loadDataFromLocal();
    _listenToFirestore();
    return 0.0;
  }

  void _listenToFirestore() {
    _firestoreService.getBankBalanceStream().listen((balance) {
      if (balance != null) {
        state = balance;
        _saveToLocalOnly(balance);
      }
    });
  }

  Future<void> updateBalance(double newBalance) async {
    state = newBalance;
    await _saveDataToLocal();
    await _firestoreService.updateBankBalance(newBalance);
  }

  Future<void> _saveToLocalOnly(double balance) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_savedBankBalanceKey, balance);
    } catch (e) {
      debugPrint('Save local balance error: $e');
    }
  }

  Future<void> _saveDataToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_savedBankBalanceKey, state);
      await ref.read(transactionProvider.notifier).persistDataToLocal();
    } catch (e) {
      debugPrint('Save bank balance error: $e');
    }
  }

  Future<void> _loadDataFromLocal() async {
    if (_hasHydrated) return;
    _hasHydrated = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_savedBankBalanceKey);
      if (saved != null) {
        state = saved;
      }
    } catch (e) {
      debugPrint('Load bank balance error: $e');
    }
  }
}

final bankBalanceProvider = NotifierProvider<BankBalanceNotifier, double>(() {
  return BankBalanceNotifier();
});

String get _stableApiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

// --- MAIN NAVIGATION HOST ---

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  // The lists of screens to switch between
  final List<Widget> _screens = [
    const TransactionsScreen(),
    const AiChatScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: Theme.of(context).colorScheme.primary),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble, color: Theme.of(context).colorScheme.primary),
            label: 'AI Chat',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// --- TAB 1: TRANSACTIONS SCREEN ---

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();

  String get currencySymbol => _currencySymbol(ref.read(currencyPreferenceProvider));
  String _transactionSearchQuery = '';
  String _selectedCategoryFilter = 'All';
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _voiceWords = "";
  String aiCoachInsight =
      "Tap the refresh icon to get custom financial insights from Gemini.";
  bool isAiLoading = false;
  bool isScanLoading = false;
  String _normalizeCategoryLabel(String category) {
    final normalized = category.trim().toLowerCase();

    switch (normalized) {
      case 'food':
        return 'Food';
      case 'cafe':
      case 'café':
        return 'Café';
      case 'transport':
        return 'Transport';
      case 'entertainment':
        return 'Entertainment';
      case 'shopping':
        return 'Shopping';
      default:
        return category.trim();
    }
  }

  double _convertFromInr(double inrAmount, String currencyCode) {
    final rate = _currencyToInrRate[currencyCode] ?? 1.0;
    return inrAmount / rate;
  }

  double _convertToInr(double amount, String currencyCode) {
    final rate = _currencyToInrRate[currencyCode] ?? 1.0;
    return amount * rate;
  }

  String _currencySymbol(String currencyCode) {
    return _currencySymbols[currencyCode] ?? '₹';
  }

  void _recordTransaction(String merchant, double amount, {String? category, bool isIncome = false}) {
    _firestoreService.addTransaction(merchant, amount, category ?? 'Misc', isIncome: isIncome);
  }

  void _showSmartPasteDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Smart Paste (SMS)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Paste your bank SMS here and AI will parse it.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: textController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'e.g. Rs 500.00 spent at STARBUCKS...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                parseAndAddVoiceTransaction(textController.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Parse'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final templates = [
      {'label': 'Salary', 'icon': Icons.account_balance_wallet_rounded, 'color': Colors.green, 'income': true},
      {'label': 'Rent', 'icon': Icons.home_rounded, 'color': Colors.red, 'amount': 15000.0, 'cat': 'Bills'},
      {'label': 'Starbucks', 'icon': Icons.coffee_rounded, 'color': Colors.brown, 'amount': 250.0, 'cat': 'Café'},
      {'label': 'Zomato', 'icon': Icons.fastfood_rounded, 'color': Colors.orange, 'amount': 450.0, 'cat': 'Food'},
    ];

    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: templates.length,
        itemBuilder: (context, index) {
          final t = templates[index];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () {
                if (t['income'] == true) {
                  _showAddTransactionDialog(isIncome: true);
                } else {
                  _recordTransaction(
                    t['label'] as String,
                    t['amount'] as double,
                    category: t['cat'] as String?,
                  );
                }
              },
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: (t['color'] as Color).withValues(alpha: 0.15),
                    child: Icon(t['icon'] as IconData, color: t['color'] as Color),
                  ),
                  const SizedBox(height: 6),
                  Text(t['label'] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _hydrateTransactionsOnStartup();
    _searchController.addListener(() {
      final currentQuery = _searchController.text;
      if (_transactionSearchQuery == currentQuery || !mounted) return;
      setState(() {
        _transactionSearchQuery = currentQuery;
      });
    });
  }

  Future<void> _hydrateTransactionsOnStartup() async {
    await ref.read(transactionProvider.notifier).hydrateFromLocal();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getFilteredTransactions(
    List<Map<String, dynamic>> transactions,
  ) {
    final query = _transactionSearchQuery.trim().toLowerCase();
    final minAmountFilter = double.tryParse(query);

    return transactions.where((tx) {
      final merchantName =
          tx['merchant']?.toString() ?? tx['merchantName']?.toString() ?? '';
      final storedCategory = tx['category']?.toString();
      final effectiveCategory = _normalizeCategoryLabel(
        storedCategory == null || storedCategory.trim().isEmpty
            ? getSmartCategory(merchantName).name
            : storedCategory,
      );
      final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;

      // 1) Apply the active category chip filter first.
      if (_selectedCategoryFilter != 'All' &&
          effectiveCategory != _selectedCategoryFilter) {
        return false;
      }

      // 2) Apply the free-text search / amount filter (if any).
      if (query.isEmpty) return true;

      final merchantMatch = merchantName.toLowerCase().contains(query);
      final categoryMatch = effectiveCategory.toLowerCase().contains(query);
      final amountMatch = minAmountFilter != null && amount >= minAmountFilter;

      return merchantMatch || categoryMatch || amountMatch;
    }).toList();
  }

  /// Returns the unique normalized categories present in the current
  /// transaction list, used to build the ChoiceChip filter row.
  List<String> _getAvailableCategories(
    List<Map<String, dynamic>> transactions,
  ) {
    final seen = <String>{};
    for (final tx in transactions) {
      final merchantName =
          tx['merchant']?.toString() ?? tx['merchantName']?.toString() ?? '';
      final storedCategory = tx['category']?.toString();
      final catName = _normalizeCategoryLabel(
        storedCategory == null || storedCategory.trim().isEmpty
            ? getSmartCategory(merchantName).name
            : storedCategory,
      );
      seen.add(catName);
    }
    final ordered = seen.toList()..sort();
    return <String>['All', ...ordered];
  }

  double _getCategoryTotal(String categoryName) {
    double total = 0.0;
    final transactions = ref.watch(transactionProvider);

    for (final tx in transactions) {
      final merchant = tx['merchant'] ?? '';
      final storedCategory = tx['category']?.toString();
      final catName = _normalizeCategoryLabel(
        storedCategory ?? getSmartCategory(merchant.toString()).name,
      );
      if (catName == categoryName) {
        final amt = tx['amount'] ?? 0;
        total += (amt is num) ? amt.toDouble() : 0.0;
      }
    }

    return total;
  }

  /// Aggregates the active [CachedTransaction] list into totals per
  /// normalized category, then returns a ready-to-render list of
  /// [PieChartSectionData] with a unique color per category.
  ///
  /// Falls back to a single grey "No Expenses" slice when the list is empty
  /// or every amount is zero, so the chart never visually breaks.
  static List<PieChartSectionData> buildPieSectionsFromCache(
    List<CachedTransaction> cachedTransactions,
  ) {
    final Map<String, double> categoryTotals = <String, double>{};
    double totalExpense = 0.0;

    for (final CachedTransaction tx in cachedTransactions) {
      final storedCategory = tx.category.trim();
      final catName = _normalizeCategoryStatic(
        storedCategory.isEmpty ? 'Misc' : storedCategory,
      );
      categoryTotals[catName] = (categoryTotals[catName] ?? 0) + tx.amount;
      totalExpense += tx.amount;
    }

    if (totalExpense <= 0 || categoryTotals.isEmpty) {
      return <PieChartSectionData>[
        PieChartSectionData(
          color: Colors.grey.shade300,
          value: 1,
          title: 'No Expenses',
          radius: 40,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
      ];
    }

    return categoryTotals.entries.map((MapEntry<String, double> entry) {
      final String catName = entry.key;
      final double amount = entry.value;
      final double percentage = (amount / totalExpense) * 100;

      return PieChartSectionData(
        color: _colorForCategory(catName),
        value: amount,
        title: '${percentage.toStringAsFixed(0)}%',
        radius: 45,
        titleStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  /// Centralized category → color mapping so the pie chart, legend, and
  /// category pills all stay visually consistent.
  static Color _colorForCategory(String categoryName) {
    switch (categoryName) {
      case 'Food':
        return Colors.orange;
      case 'Café':
        return Colors.brown;
      case 'Transport':
        return Colors.blue;
      case 'Entertainment':
        return Colors.purple;
      case 'Shopping':
        return Colors.pink;
      case 'Bills':
        return Colors.red;
      case 'Utilities':
        return Colors.redAccent;
      case 'Health':
        return Colors.green;
      case 'Travel':
        return Colors.indigo;
      default:
        return Colors.blueGrey;
    }
  }

  /// Pure, side-effect-free version of [_normalizeCategoryLabel] usable from
  /// static helpers (e.g. [buildPieSectionsFromCache]).
  static String _normalizeCategoryStatic(String category) {
    final String normalized = category.trim().toLowerCase();
    switch (normalized) {
      case 'food':
        return 'Food';
      case 'cafe':
      case 'café':
        return 'Café';
      case 'transport':
        return 'Transport';
      case 'entertainment':
        return 'Entertainment';
      case 'shopping':
        return 'Shopping';
      case 'bills':
      case 'utilities':
        return 'Bills';
      case 'health':
      case 'medical':
        return 'Health';
      case 'travel':
        return 'Travel';
      default:
        return category.trim().isEmpty ? 'Misc' : category.trim();
    }
  }

  List<PieChartSectionData> getShowingSections() {
    final transactions = ref.watch(transactionProvider);
    final List<CachedTransaction> cached = transactions
        .map(
          (tx) => CachedTransaction(
            id: '${tx['date']}_${tx['merchant']}_${tx['amount']}',
            merchantName:
                tx['merchant']?.toString() ??
                tx['merchantName']?.toString() ??
                'Unknown',
            category:
                tx['category']?.toString() ??
                getSmartCategory((tx['merchant'] ?? '').toString()).name,
            amount: (tx['amount'] as num?)?.toDouble() ?? 0.0,
            timestamp:
                DateTime.tryParse(tx['date']?.toString() ?? '') ??
                DateTime.now(),
            currencyCode: ref.read(currencyPreferenceProvider),
          ),
        )
        .toList();
    return buildPieSectionsFromCache(cached);
  }

  Widget _buildLegendItem(Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseTrendChart(Color cardColor, Color textColor, bool isDarkMode) {
    return Card(
      color: cardColor,
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.donut_large_rounded,
                  color: isDarkMode ? Colors.tealAccent : Colors.teal,
                ),
                const SizedBox(width: 8),
                Text(
                  'Expense Breakdown',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 520;
                final chart = SizedBox(
                  height: 190,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 42,
                      startDegreeOffset: -90,
                      sections: getShowingSections(),
                    ),
                    swapAnimationDuration: const Duration(milliseconds: 650),
                    swapAnimationCurve: Curves.easeOutCubic,
                  ),
                );
                final legend = Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    _buildLegendItem(Colors.orange, 'Food'),
                    _buildLegendItem(Colors.brown, 'Caf\u00e9'),
                    _buildLegendItem(Colors.blue, 'Transport'),
                    _buildLegendItem(Colors.purple, 'Entertainment'),
                    _buildLegendItem(Colors.pink, 'Shopping'),
                  ],
                );

                if (isWide) {
                  return Row(
                    children: [
                      Expanded(flex: 4, child: chart),
                      const SizedBox(width: 18),
                      Expanded(flex: 3, child: legend),
                    ],
                  );
                }

                return Column(
                  children: [
                    chart,
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: legend),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsInsightCard(
    Color cardColor,
    Color textColor,
    Map<String, double> categoryBudgets,
    String currencyCode,
    bool isDarkMode,
  ) {
    final Map<String, double> spentByCategory = {};
    double totalSpent = 0.0;
    double totalBudget = 0.0;

    categoryBudgets.forEach((category, budget) {
      final spent = _getCategoryTotal(category);
      spentByCategory[category] = spent;
      totalSpent += spent;
      totalBudget += budget;
    });

    String topCategory = 'General';
    double topSpent = 0.0;
    double topBudget = 1.0;

    spentByCategory.forEach((category, spent) {
      if (spent >= topSpent) {
        topSpent = spent;
        topCategory = category;
        topBudget = categoryBudgets[category] ?? 1.0;
      }
    });

    final overallRatio = totalBudget > 0 ? totalSpent / totalBudget : 0.0;
    final topCategoryRatio = topBudget > 0 ? topSpent / topBudget : 0.0;
    final allUnderHalf = categoryBudgets.entries.every((entry) {
      final spent = spentByCategory[entry.key] ?? 0.0;
      return spent < (entry.value * 0.5);
    });
    final convertedTopSpent = _convertFromInr(topSpent, currencyCode);
    final currencySymbol = _currencySymbol(currencyCode);

    final bool nearLimit = topCategoryRatio >= 0.8;
    final IconData insightIcon = nearLimit
        ? Icons.lightbulb_rounded
        : Icons.show_chart_rounded;
    final Color accentColor = nearLimit
        ? (isDarkMode ? Colors.orangeAccent : Colors.deepOrange)
        : Theme.of(context).colorScheme.primary;

    final String insightText = allUnderHalf
        ? '🎉 Great job, Prathik! You are managing your budget excellently this week.'
        : nearLimit
        ? '💡 Tip: Your spending is highest in $topCategory this month. Consider slowing down here!'
        : '💡 Insight: $topCategory is your most active spend category right now. Keep an eye on it as your total budget usage reaches ${(overallRatio * 100).toStringAsFixed(0)}%.';

    return Card(
      color: cardColor,
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(insightIcon, color: accentColor),
                const SizedBox(width: 8),
                Text(
                  'AI Financial Coach',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              insightText,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Top spend in $topCategory: $currencySymbol${convertedTopSpent.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Overall budget usage: ${(overallRatio * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetProgressBar(
    String category,
    double budget,
    String currencyCode,
    bool isDarkMode,
  ) {
    final spent = _getCategoryTotal(category);
    final percent = budget > 0 ? (spent / budget) : 0.0;
    final visualPercent = percent > 1.0 ? 1.0 : percent;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    final symbol = _currencySymbol(currencyCode);
    final convertedSpent = _convertFromInr(spent, currencyCode);
    final convertedBudget = _convertFromInr(budget, currencyCode);

    final Color progressColor = percent > 0.80 ? Colors.red : Colors.teal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                category,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: textColor,
                ),
              ),
              Text(
                "$symbol${convertedSpent.toStringAsFixed(0)} / $symbol${convertedBudget.toStringAsFixed(0)} (${(percent * 100).toStringAsFixed(0)}%)",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: percent >= 1.0
                      ? Colors.red
                      : (isDarkMode ? Colors.grey[400] : Colors.grey[700]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: visualPercent,
              minHeight: 10,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchAICoachInsight() async {
    setState(() {
      isAiLoading = true;
      aiCoachInsight = "Analyzing your spending history and tracking limits...";
    });

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_stableApiKey',
      );
      final transactions = ref.read(transactionProvider);
      final categoryBudgets = ref.read(budgetLimitsProvider);
      final currencyCode = ref.read(currencyPreferenceProvider);
      final symbol = _currencySymbol(currencyCode);
      final dataReport = StringBuffer();

      categoryBudgets.forEach((category, budget) {
        final spent = _getCategoryTotal(category);
        final convertedSpent = _convertFromInr(spent, currencyCode);
        final convertedBudget = _convertFromInr(budget, currencyCode);
        dataReport.writeln(
          "- $category: Spent $symbol${convertedSpent.toStringAsFixed(2)} out of a budget of $symbol${convertedBudget.toStringAsFixed(2)}.",
        );
      });

      for (final tx in transactions.take(5)) {
        final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
        final convertedAmount = _convertFromInr(amount, currencyCode);
        dataReport.writeln(
          "- ${tx['merchant']}: $symbol${convertedAmount.toStringAsFixed(2)} on ${tx['date']?.toString().split(' ')[0]}",
        );
      }

      final prompt =
          """
You are a witty, smart, and slightly brutally honest AI Personal Finance Coach embedded inside a dashboard app.
Review this user spending data below and provide a concise, single-paragraph (max 3 sentences) takeaway insight.
Call out any category where they are dangerously close to or exceeding their budget limit.
Keep it actionable, highly engaging, and speak directly to them.

Data:
${dataReport.toString()}
""";

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": prompt},
              ],
            },
          ],
        }),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final String aiText =
            responseData['candidates'][0]['content']['parts'][0]['text'];

        setState(() {
          aiCoachInsight = aiText.trim();
          isAiLoading = false;
        });
      } else {
        setState(() {
          aiCoachInsight =
              "Error: ${response.statusCode}\nDetails: ${response.body}";
          isAiLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        aiCoachInsight = "Connection error occurred: $e";
        isAiLoading = false;
      });
    }
  }

  Widget _buildAICoachCard(Color cardColor, Color textColor, bool isDarkMode) {
    return Card(
      color: cardColor,
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: isDarkMode
                ? [Theme.of(context).colorScheme.primaryContainer, Theme.of(context).cardColor]
                : [Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3), Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.psychology_rounded,
                      color: Theme.of(context).colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "AI Financial Advisor",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                isAiLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                    : IconButton(
                        icon: Icon(
                          Icons.refresh_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: _fetchAICoachInsight,
                      ),
              ],
            ),
            const Divider(height: 20),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              child: Text(
                aiCoachInsight,
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanReceiptWithAI() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );

    if (photo == null) return;

    setState(() {
      isScanLoading = true;
    });

    try {
      final imageBytes = await photo.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_stableApiKey',
      );

      final Map<String, dynamic> requestBody = {
        "contents": [
          {
            "parts": [
              {
                "text":
                    "Analyze this receipt image. Extract the merchant name, the total amount spent, and the category (e.g., Food, Cafe, Utilities, Transport, Entertainment). Respond ONLY with a valid, raw JSON object exactly like this: {\"merchant\": \"Name\", \"amount\": 0.0, \"category\": \"Category\"}. Do not wrap it in markdown code blocks.",
              },
              {
                "inlineData": {"mimeType": "image/jpeg", "data": base64Image},
              },
            ],
          },
        ],
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final rawJsonText =
            responseData['candidates'][0]['content']['parts'][0]['text']
                .toString();
        final extractedData = jsonDecode(rawJsonText.trim());
        final merchantName =
            extractedData['merchant']?.toString() ?? 'Unknown Merchant';
        final amountValue = extractedData['amount'];
        final parsedAmount = amountValue is num ? amountValue.toDouble() : 0.0;
        final rawCategory = extractedData['category']?.toString() ?? '';
        final category = _normalizeCategoryLabel(rawCategory);

        final transactionDate = DateTime.now().toString();

        ref
            .read(transactionProvider.notifier)
            .addTransaction(
              merchantName,
              parsedAmount,
              category: category.isEmpty ? null : category,
              date: transactionDate,
            );

        if (!mounted) return;
        final categoryBudgets = ref.read(budgetLimitsProvider);
        if (categoryBudgets.containsKey(category)) {
          final currencyCode = ref.read(currencyPreferenceProvider);
          final symbol = _currencySymbol(currencyCode);
          final categoryBudgetLimit = categoryBudgets[category]!;
          final updatedCategorySpent = _getCategoryTotal(category);
          final convertedSpent = _convertFromInr(
            updatedCategorySpent,
            currencyCode,
          );
          final convertedBudget = _convertFromInr(
            categoryBudgetLimit,
            currencyCode,
          );
          final budgetUsage = categoryBudgetLimit > 0
              ? updatedCategorySpent / categoryBudgetLimit
              : 0.0;

          if (budgetUsage >= 1.0 || budgetUsage >= 0.8) {
            final isCritical = budgetUsage >= 1.0;
            final alertColor = isCritical
                ? Colors.redAccent
                : Colors.orangeAccent;
            final thresholdLabel = isCritical ? '100%' : '80%';
            final message = isCritical
                ? '⚠️ Budget exceeded for $category: $symbol${convertedSpent.toStringAsFixed(0)} / $symbol${convertedBudget.toStringAsFixed(0)} used.'
                : '⚠️ Budget warning for $category: $symbol${convertedSpent.toStringAsFixed(0)} / $symbol${convertedBudget.toStringAsFixed(0)} used ($thresholdLabel+).';

            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(
                  backgroundColor: alertColor,
                  behavior: SnackBarBehavior.floating,
                  content: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              );
          }
        }

        setState(() {
          isScanLoading = false;
        });

        _fetchAICoachInsight();
      } else {
        debugPrint("OCR Scan Failed: ${response.body}");
        setState(() {
          isScanLoading = false;
        });
      }
    } catch (e) {
      debugPrint("OCR Error: $e");
      if (!mounted) return;
      setState(() {
        isScanLoading = false;
      });
    }
  }

  String _escapeHtml(String value) {
    return const HtmlEscape().convert(value);
  }

  Future<void> _exportToCSV() async {
    final transactions = ref.read(transactionProvider);

    try {
      final StringBuffer csvBuilder = StringBuffer();
      csvBuilder.writeln('Date,Merchant,Category,Amount');

      for (final tx in transactions) {
        final date = tx['date']?.toString().split(' ').first ?? '';
        final merchant = tx['merchant']?.toString() ?? 'Unknown Merchant';
        final storedCategory = tx['category']?.toString();
        final categoryName = _normalizeCategoryLabel(
          storedCategory == null || storedCategory.trim().isEmpty
              ? getSmartCategory(merchant).name
              : storedCategory,
        );
        final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;

        final safeDate = '"${date.replaceAll('"', '""')}"';
        final safeMerchant = '"${merchant.replaceAll('"', '""')}"';
        final safeCategory = '"${categoryName.replaceAll('"', '""')}"';
        final safeAmount = amount.toStringAsFixed(2);

        csvBuilder.writeln('$safeDate,$safeMerchant,$safeCategory,$safeAmount');
      }

      final blob = html.Blob([csvBuilder.toString()], 'text/csv;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);

      html.AnchorElement(href: url)
        ..setAttribute(
          'download',
          'finance_report_${DateTime.now().millisecondsSinceEpoch}.csv',
        )
        ..click();

      html.Url.revokeObjectUrl(url);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CSV export started. Check your downloads.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('CSV export error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to export CSV right now: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _exportToPDF() {
    final transactions = ref.read(transactionProvider);
    final totalSpent = transactions.fold<double>(
      0,
      (sum, item) => sum + (item['amount'] as num).toDouble(),
    );

    final tableRows = transactions
        .map((tx) {
          final merchant = tx['merchant'] as String;
          final amount = (tx['amount'] as num).toDouble();
          final cat = getSmartCategory(merchant);
          return '''
      <tr>
        <td>${_escapeHtml(tx['date'].toString())}</td>
        <td><strong>${_escapeHtml(merchant)}</strong></td>
        <td><span style="color: grey;">${_escapeHtml(cat.name)}</span></td>
        <td style="text-align: right; color: #d32f2f;">- ₹${amount.toStringAsFixed(2)}</td>
      </tr>
    ''';
        })
        .join('');

    final htmlContent =
        '''
    <html>
    <head>
      <title>Financial Ledger Summary Report</title>
      <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; padding: 30px; color: #333; }
        .header { border-bottom: 2px solid #009688; padding-bottom: 12px; margin-bottom: 24px; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { padding: 12px; border-bottom: 1px solid #ddd; text-align: left; }
        th { background-color: #f5f5f5; color: #009688; }
        .total-box { margin-top: 30px; text-align: right; font-size: 1.3em; font-weight: bold; }
      </style>
    </head>
    <body>
      <div class="header">
        <h2>AI Finance Dashboard - Ledger Report</h2>
        <p>Generated on: ${DateTime.now().toString().split('.')[0]}</p>
      </div>
      <table>
        <thead>
          <tr><th>Date</th><th>Merchant</th><th>Category</th><th style="text-align: right;">Amount</th></tr>
        </thead>
        <tbody>$tableRows</tbody>
      </table>
      <div class="total-box">Aggregate Period Expenses: ₹${totalSpent.toStringAsFixed(2)}</div>
      <script>window.print();</script>
    </body>
    </html>
  ''';

    final blob = html.Blob([htmlContent], 'text/html');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.window.open(url, '_blank');
    html.Url.revokeObjectUrl(url);
  }

  void _showAddTransactionDialog({bool isIncome = false}) {
    final merchantController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isIncome ? 'Add New Income' : 'Add New Expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: merchantController,
              decoration: const InputDecoration(labelText: 'Source/Merchant'),
            ),
            TextField(
              controller: amountController,
              decoration: InputDecoration(labelText: 'Amount ($currencySymbol)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (merchantController.text.isNotEmpty &&
                  amountController.text.isNotEmpty) {
                final amt = double.tryParse(amountController.text) ?? 0.0;
                _recordTransaction(merchantController.text, amt, isIncome: isIncome);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void parseAndAddVoiceTransaction(String text) {
    final lowerText = text.toLowerCase();
    double? parsedAmount;
    String parsedMerchant = "Unknown";

    final amountRegex = RegExp(r'\b\d+(?:\.\d+)?\b');
    final matches = amountRegex.allMatches(lowerText);
    if (matches.isNotEmpty) {
      parsedAmount = double.tryParse(matches.first.group(0) ?? '');
    }

    final merchantRegex = RegExp(r'\b(?:at|to|on|from)\s+([a-zA-Z0-9\s]+)');
    final merchantMatch = merchantRegex.firstMatch(lowerText);
    if (merchantMatch != null && merchantMatch.groupCount >= 1) {
      parsedMerchant = merchantMatch.group(1)!.trim();
      parsedMerchant = parsedMerchant
          .split(' ')
          .map((word) {
            if (word.isEmpty) return word;
            return word[0].toUpperCase() + word.substring(1);
          })
          .join(' ');
    }

    if (parsedAmount != null) {
      _recordTransaction(
        parsedMerchant == "Unknown" ? "Voice Transaction" : parsedMerchant,
        parsedAmount,
      );
    }
  }

  void _listen() async {
    if (!_isListening) {
      final available = await _speech.initialize(
        onStatus: (val) => debugPrint('Speech status: $val'),
        onError: (val) => debugPrint('Speech error: $val'),
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              _voiceWords = val.recognizedWords;
              if (val.finalResult) {
                _isListening = false;
              }
            });

            if (val.finalResult) {
              parseAndAddVoiceTransaction(_voiceWords);
            }
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryBudgets = ref.watch(budgetLimitsProvider);
    final monthlyBudgetCap = ref.watch(monthlyBudgetCapProvider);
    final bankBalance = ref.watch(bankBalanceProvider);
    final currencyCode = ref.watch(currencyPreferenceProvider);
    final currencySymbol = _currencySymbol(currencyCode);

    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDarkMode ? Colors.grey[850]! : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return StreamBuilder<List<TransactionModel>>(
      stream: _firestoreService.getTransactionsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final transactions = snapshot.data?.map((tx) => {
          'id': tx.id,
          'merchant': tx.merchant,
          'amount': tx.amount,
          'category': tx.category,
          'date': tx.date.toString(),
          'isIncome': tx.isIncome,
        }).toList() ?? [];

        final filteredTransactions = _getFilteredTransactions(transactions);
        final availableCategories = _getAvailableCategories(transactions);
        double totalExpenses = 0.0;
        double totalIncome = 0.0;

        for (var tx in transactions) {
          final amt = (tx['amount'] as num).toDouble();
          if (tx['isIncome'] == true) {
            totalIncome += amt;
          } else {
            totalExpenses += amt;
          }
        }

        double currentBalance = (bankBalance + totalIncome) - totalExpenses;
        final convertedCurrentBalance = _convertFromInr(
          currentBalance,
          currencyCode,
        );
        final convertedMonthlyCap = _convertFromInr(monthlyBudgetCap, currencyCode);
        final convertedTotalExpenses = _convertFromInr(totalExpenses, currencyCode);
        final convertedTotalIncome = _convertFromInr(totalIncome, currencyCode);
        final convertedBankBalance = _convertFromInr(bankBalance, currencyCode);

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'AI Finance Dashboard',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            actions: [
              Icon(isDarkMode ? Icons.dark_mode : Icons.light_mode),
              Switch(
                value: isDarkMode,
                onChanged: (val) => ref.read(themeProvider.notifier).toggleTheme(val),
                activeThumbColor: Colors.tealAccent,
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Logout',
                onPressed: () => FirebaseAuth.instance.signOut(),
              ),
            ],
          ),
          body: SingleChildScrollView(
              child: Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.teal.shade700, Colors.teal.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.teal.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Total Balance',
                              style: TextStyle(color: Colors.white70, fontSize: 16),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white70, size: 18),
                              tooltip: 'Update Bank Balance',
                              onPressed: () {
                                final controller = TextEditingController(
                                  text: convertedBankBalance.toStringAsFixed(0),
                                );
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Set Current Bank Balance'),
                                    content: TextField(
                                      controller: controller,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Bank Balance ($currencySymbol)',
                                        border: const OutlineInputBorder(),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          final val = double.tryParse(controller.text);
                                          if (val != null) {
                                            final inrVal = _convertToInr(val, currencyCode);
                                            ref.read(bankBalanceProvider.notifier).updateBalance(inrVal);
                                            Navigator.pop(context);
                                          }
                                        },
                                        child: const Text('Set'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(
                            _isListening
                                ? Icons.mic_rounded
                                : Icons.mic_none_rounded,
                            color: _isListening ? Colors.red : Colors.white,
                          ),
                          onPressed: _listen,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$currencySymbol${convertedCurrentBalance.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.2,
                              ),
                              child: const Icon(
                                Icons.arrow_downward,
                                color: Colors.greenAccent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Income',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      '$currencySymbol${(convertedMonthlyCap + convertedTotalIncome).toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.white70, size: 16),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () {
                                        final controller = TextEditingController(
                                          text: convertedMonthlyCap.toStringAsFixed(0),
                                        );
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Update Monthly Income'),
                                            content: TextField(
                                              controller: controller,
                                              keyboardType: TextInputType.number,
                                              decoration: InputDecoration(
                                                labelText: 'Monthly Income ($currencySymbol)',
                                                border: const OutlineInputBorder(),
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text('Cancel'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () {
                                                  final val = double.tryParse(controller.text);
                                                  if (val != null && val > 0) {
                                                    final inrVal = _convertToInr(val, currencyCode);
                                                    ref.read(monthlyBudgetCapProvider.notifier).updateBudgetCap(inrVal);
                                                    Navigator.pop(context);
                                                  }
                                                },
                                                child: const Text('Update'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.2,
                              ),
                              child: const Icon(
                                Icons.arrow_upward,
                                color: Colors.redAccent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Expenses',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  '$currencySymbol${convertedTotalExpenses.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildAICoachCard(cardColor, textColor, isDarkMode),
              const Padding(
                padding: EdgeInsets.only(left: 16.0, top: 12, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Quick Templates',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ),
              ),
              _buildQuickActions(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 6.0,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _exportToCSV,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Export Analytics Report'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDarkMode
                          ? Colors.teal[600]
                          : Colors.teal,
                      foregroundColor: Colors.white,
                      elevation: 1,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildExpenseTrendChart(cardColor, textColor, isDarkMode),
              _buildAnalyticsInsightCard(
                cardColor,
                textColor,
                categoryBudgets,
                currencyCode,
                isDarkMode,
              ),
              Card(
                margin: const EdgeInsets.all(16.0),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 4.0,
                        ),
                        child: Text(
                          'Monthly Category Budgets',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ),
                      const Divider(),
                      ...categoryBudgets.entries.map((entry) {
                        return _buildBudgetProgressBar(
                          entry.key,
                          entry.value,
                          currencyCode,
                          isDarkMode,
                        );
                      }),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Transactions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.table_view_rounded,
                            color: Colors.green,
                          ),
                          tooltip: 'Export CSV Spreadsheet',
                          onPressed: _exportToCSV,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.picture_as_pdf_rounded,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'Print Summary PDF',
                          onPressed: _exportToPDF,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search by category, merchant, or amount...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              FocusScope.of(context).unfocus();
                            },
                          ),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredTransactions.length,
                itemBuilder: (context, index) {
                  final tx = filteredTransactions[index];
                  final merchantName =
                      tx['merchant']?.toString() ??
                      tx['merchantName']?.toString() ??
                      'Unknown Merchant';
                  final smartCategory = getSmartCategory(merchantName);
                  final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                  final convertedAmount = _convertFromInr(amount, currencyCode);
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: smartCategory.color.withValues(
                          alpha: 0.15,
                        ),
                        child: Icon(
                          smartCategory.icon,
                          color: smartCategory.color,
                        ),
                      ),
                      title: Text(
                        merchantName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: smartCategory.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            smartCategory.name,
                            style: TextStyle(
                              color: smartCategory.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      trailing: Text(
                        '${tx['isIncome'] == true ? '+' : '-'} $currencySymbol${convertedAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: tx['isIncome'] == true ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton(
              heroTag: 'voiceTransaction',
              onPressed: _listen,
              backgroundColor: _isListening ? Colors.red : Colors.blue,
              child: Icon(
                _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'scanReceipt',
              onPressed: isScanLoading ? null : _scanReceiptWithAI,
              backgroundColor: Colors.deepPurple,
              child: isScanLoading
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : const Icon(Icons.camera_alt, color: Colors.white),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'smartPaste',
              onPressed: _showSmartPasteDialog,
              backgroundColor: Colors.orange,
              child: const Icon(Icons.paste_rounded, color: Colors.white),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'addTransaction',
              onPressed: _showAddTransactionDialog,
              backgroundColor: Colors.teal,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ],
        ),
      );
    },
  );
}
}

// --- TAB 3: SETTINGS / PROFILE SCREEN ---

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _monthlyCapController;
  final Map<String, TextEditingController> _categoryControllers = {};
  bool _isSyncing = false;
  String lastSyncedTimestamp = 'July 1, 2026';

  double _convertFromInr(double inrAmount, String currencyCode) {
    final rate = _currencyToInrRate[currencyCode] ?? 1.0;
    return inrAmount / rate;
  }

  double _convertToInr(double amount, String currencyCode) {
    final rate = _currencyToInrRate[currencyCode] ?? 1.0;
    return amount * rate;
  }

  String _currencySymbol(String currencyCode) {
    return _currencySymbols[currencyCode] ?? '₹';
  }

  String _formatSyncTimestamp(DateTime timestamp) {
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${monthNames[timestamp.month - 1]} ${timestamp.day}, ${timestamp.year}';
  }

  void _refreshBudgetControllers(String currencyCode) {
    final monthlyCapInInr = ref.read(monthlyBudgetCapProvider);
    final categoryBudgetsInInr = ref.read(budgetLimitsProvider);

    _monthlyCapController.text = _convertFromInr(
      monthlyCapInInr,
      currencyCode,
    ).toStringAsFixed(2);

    for (final entry in categoryBudgetsInInr.entries) {
      final controller = _categoryControllers.putIfAbsent(
        entry.key,
        () => TextEditingController(),
      );
      controller.text = _convertFromInr(
        entry.value,
        currencyCode,
      ).toStringAsFixed(2);
    }
  }

  @override
  void initState() {
    super.initState();
    final monthlyCap = ref.read(monthlyBudgetCapProvider);
    final budgets = ref.read(budgetLimitsProvider);
    final currencyCode = ref.read(currencyPreferenceProvider);

    _monthlyCapController = TextEditingController(
      text: _convertFromInr(monthlyCap, currencyCode).toStringAsFixed(2),
    );
    for (final entry in budgets.entries) {
      _categoryControllers[entry.key] = TextEditingController(
        text: _convertFromInr(entry.value, currencyCode).toStringAsFixed(2),
      );
    }
  }

  @override
  void dispose() {
    _monthlyCapController.dispose();
    for (final controller in _categoryControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _buildProfileHeader() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: Colors.teal,
              child: Icon(Icons.person_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Prathik',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Student / Premium User',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAllBudgetInputs() async {
    final currencyCode = ref.read(currencyPreferenceProvider);
    final monthlyCap = double.tryParse(_monthlyCapController.text.trim());
    if (monthlyCap != null && monthlyCap > 0) {
      final monthlyCapInInr = _convertToInr(monthlyCap, currencyCode);
      await ref
          .read(monthlyBudgetCapProvider.notifier)
          .updateBudgetCap(monthlyCapInInr);
    }

    for (final entry in _categoryControllers.entries) {
      final parsed = double.tryParse(entry.value.text.trim());
      if (parsed != null && parsed > 0) {
        final parsedInInr = _convertToInr(parsed, currencyCode);
        await ref
            .read(budgetLimitsProvider.notifier)
            .updateCategoryLimit(entry.key, parsedInInr);
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Budget settings saved successfully.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Backend client used to push the local transaction batch to the cloud.
  /// Reads the endpoint from `.env` when available so staging/production
  /// can be switched without recompiling.
  late final CloudSyncService _cloudSync = CloudSyncService(
    endpoint: Uri.parse(
      dotenv.env['CLOUD_SYNC_ENDPOINT'] ??
          'https://api.your-backend.example.com/v1/sync',
    ),
    authToken: dotenv.env['CLOUD_SYNC_TOKEN'] ?? '',
    timeout: const Duration(seconds: 15),
    maxRetries: 2,
  );

  /// User id sent along with each sync payload. Pull this from a real auth
  /// provider in production; for now it falls back to a stable local id.
  String get _cloudUserId =>
      dotenv.env['CLOUD_SYNC_USER_ID'] ?? 'prathik';

  Future<void> _syncDataToCloud() async {
    if (_isSyncing) return;

    setState(() {
      _isSyncing = true;
    });

    try {
      // 1) Hydrate the active transaction list from the local database.
      final localDb = LocalDatabaseService();
      await localDb.initDatabase();
      final cachedBatch = await localDb.fetchStoredTransactions();

      // 2) Push the batch to the backend.
      final CloudSyncResult result = await _cloudSync.pushTransactionBatch(
        cachedBatch,
        userId: _cloudUserId,
      );

      if (!mounted) return;

      setState(() {
        lastSyncedTimestamp = _formatSyncTimestamp(result.timestamp);
      });

      // 3) Surface the outcome to the user.
      final Color snackColor = result.isSuccess
          ? Colors.teal
          : (result.status == CloudSyncStatus.unauthorized
              ? Colors.orange
              : Colors.redAccent);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: snackColor,
          behavior: SnackBarBehavior.floating,
          content: Text(result.message),
        ),
      );
    } catch (e) {
      debugPrint('Cloud sync error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud backup could not be completed right now.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Widget _buildCloudSyncCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_done_rounded, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Cloud Backup & Sync',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.link_rounded,
                  size: 18,
                  color: Colors.green.shade700,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Status: Linked',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: Colors.teal.shade700,
                ),
                const SizedBox(width: 8),
                Text(
                  'Last Synced: $lastSyncedTimestamp',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSyncing ? null : _syncDataToCloud,
                icon: _isSyncing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withOpacity(0.95),
                          ),
                        ),
                      )
                    : const Icon(Icons.cloud_upload_rounded),
                label: Text(_isSyncing ? 'Syncing Data...' : 'Sync Data Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final budgetLimits = ref.watch(budgetLimitsProvider);
    final selectedCurrency = ref.watch(currencyPreferenceProvider);
    final currencySymbol = _currencySymbol(selectedCurrency);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Profile'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'Preferred Currency',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: DropdownButtonFormField<String>(
                value: selectedCurrency,
                items: _supportedCurrencies.map((currency) {
                  return DropdownMenuItem<String>(
                    value: currency,
                    child: Text('$currency (${_currencySymbol(currency)})'),
                  );
                }).toList(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.currency_exchange_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) async {
                  if (value == null) return;
                  await ref
                      .read(currencyPreferenceProvider.notifier)
                      .setCurrencyCode(value);
                  if (!mounted) return;
                  setState(() {
                    _refreshBudgetControllers(value);
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'Monthly Budget Cap',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextField(
                controller: _monthlyCapController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Total Monthly Cap ($currencySymbol)',
                  prefixIcon: const Icon(Icons.savings_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  final parsed = double.tryParse(value.trim());
                  if (parsed != null && parsed > 0) {
                    final parsedInInr = _convertToInr(parsed, selectedCurrency);
                    ref
                        .read(monthlyBudgetCapProvider.notifier)
                        .updateBudgetCap(parsedInInr);
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Text(
                'Category Limits',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            ...budgetLimits.entries.map((entry) {
              final controller = _categoryControllers.putIfAbsent(
                entry.key,
                () => TextEditingController(
                  text: _convertFromInr(
                    entry.value,
                    selectedCurrency,
                  ).toStringAsFixed(2),
                ),
              );

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 6.0,
                ),
                child: TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '${entry.key} Limit ($currencySymbol)',
                    prefixIcon: const Icon(Icons.tune_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (value) {
                    final parsed = double.tryParse(value.trim());
                    if (parsed != null && parsed > 0) {
                      final parsedInInr = _convertToInr(
                        parsed,
                        selectedCurrency,
                      );
                      ref
                          .read(budgetLimitsProvider.notifier)
                          .updateCategoryLimit(entry.key, parsedInInr);
                    }
                  },
                ),
              );
            }),
            _buildCloudSyncCard(),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saveAllBudgetInputs,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save Budget Settings'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- TAB 2: AI CHAT SCREEN (INTERACTIVE CHAT UI & RULE ENGINE) ---

// --- TAB 2: AI CHAT SCREEN (GEMINI CONFIGURATION) ---

// 1. THIS IS THE MAIN WIDGET ENTRY POINT (Add this block if it's missing!)
class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

// 2. THIS IS THE STATE OBJECT MANAGEMENT
class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final TextEditingController _messageController = TextEditingController();

  // 1. Added State Variables
  bool _isLoading = false;
  final Map<String, double> categoryBudgets = {
    'Food': 5000.0,
    'Caf\u00e9': 2000.0,
    'Transport': 3000.0,
    'Entertainment': 4000.0,
    'Shopping': 6000.0,
  };
  final List<Map<String, String>> _messages = [
    {
      "sender": "ai",
      "text":
          "Hello! I am your AI Finance Assistant. Ask me anything about your expenses or dynamic balance!",
    },
  ];

  double _getCategoryTotal(String categoryName) {
    double total = 0.0;
    final transactions = ref.read(transactionProvider);

    for (final tx in transactions) {
      final merchant = tx['merchant'] ?? '';
      final cat = getSmartCategory(merchant.toString());
      if (cat.name == categoryName) {
        final amt = tx['amount'] ?? 0;
        total += (amt is num) ? amt.toDouble() : 0.0;
      }
    }

    return total;
  }

  Future<void> _sendMessageToGemini(String text) async {
    if (text.trim().isEmpty) return;

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_stableApiKey',
      );

      StringBuffer contextReport = StringBuffer();
      categoryBudgets.forEach((category, budget) {
        double spent = _getCategoryTotal(category);
        contextReport.writeln(
          "- $category: Spent ₹$spent out of a budget of ₹$budget.",
        );
      });

      final prompt =
          """
You are a helpful personal finance chat assistant inside a dashboard app.
Answer the user's question briefly based on their data.

Data:
${contextReport.toString()}

Question: $text
""";

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": prompt},
              ],
            },
          ],
        }),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final String replyText =
            responseData['candidates'][0]['content']['parts'][0]['text'];

        setState(() {
          _messages.add({'sender': 'user', 'text': text});
          _messages.add({"sender": "ai", "text": replyText.trim()});
        });
      } else {
        print("Error: ${response.body}");
      }
    } catch (e) {
      print("Exception: $e");
    }
  }

  // 2. The New Asynchronous Gemini Send Message Function
  Future<void> _sendMessage() async {
    final query = _messageController.text.trim();
    if (query.isEmpty || _isLoading) return;

    final currentTransactions = ref.read(transactionProvider);

    setState(() {
      _messages.add({"sender": "user", "text": query});
      _isLoading = true;
    });

    _messageController.clear();

    try {
      // 🟢 CHANGE THIS SPECIFIC BLOCK:
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_stableApiKey',
      );
      // The rest of your code (double totalExpenses = ...) stays exactly the same!

      double totalExpenses = currentTransactions.fold(
        0.0,
        (sum, item) => sum + (item["amount"] as num).toDouble(),
      );
      final monthlyBudgetCap = ref.read(monthlyBudgetCapProvider);
      final bankBalance = ref.read(bankBalanceProvider);
      double dynamicBalance = bankBalance - totalExpenses;

      String transactionContext =
          "You are a helpful financial assistant app. Here is the user's current live transaction data:\n";
      transactionContext += "Total Income base: ₹${monthlyBudgetCap.toStringAsFixed(2)}\n";
      transactionContext += "Manual Bank Balance base: ₹${bankBalance.toStringAsFixed(2)}\n";
      transactionContext +=
          "Current Calculated Available Balance: ₹${dynamicBalance.toStringAsFixed(2)}\n";
      transactionContext +=
          "Current Calculated Balance: ₹${dynamicBalance.toStringAsFixed(2)}\n";
      transactionContext +=
          "Total Expenses: ₹${totalExpenses.toStringAsFixed(2)}\n\n";
      transactionContext += "Transaction Records:\n";

      for (var tx in currentTransactions) {
        transactionContext +=
            "- ${tx['date']}: ${tx['merchant']} for ₹${tx['amount']}\n";
      }

      transactionContext +=
          "\nAnswer the user's question accurately using ONLY the structured financial data provided above. Be concise and conversational. User question: $query";

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": transactionContext},
              ],
            },
          ],
        }),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final String replyText =
            responseData['candidates'][0]['content']['parts'][0]['text'];

        setState(() {
          _messages.add({"sender": "ai", "text": replyText.trim()});
        });
      } else {
        setState(() {
          _messages.add({
            "sender": "ai",
            "text":
                "Chat Error: ${response.statusCode}\nDetails: ${response.body}",
          });
        });
      }
    } catch (e) {
      setState(() {
        _messages.add({
          "sender": "ai",
          "text": "Error connecting to Gemini API. Details: $e",
        });
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 3. UI Layout Definition
  // 3. UI Layout Definition
  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Gemini Financial Assistant',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          // 🟢 INSERT THE CLEAR CHAT BUTTON HERE:
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.teal),
            tooltip: 'Clear Chat',
            onPressed: () {
              setState(() {
                _messages.clear();
                _messages.add({
                  "sender": "ai",
                  "text":
                      "Hello! I am your AI Finance Assistant. Ask me anything about your expenses or dynamic balance!",
                });
              });
            },
          ),
          // Your existing padding block from image_7e8f5e.png remains perfectly intact below:
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Text(
                'Txs: ${transactions.length}',
                style: const TextStyle(
                  color: Colors.teal,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // CHAT MESSAGES STREAM LIST
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg["sender"] == "user";

                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isUser
                            ? const Radius.circular(16)
                            : Radius.zero,
                        bottomRight: isUser
                            ? Radius.zero
                            : const Radius.circular(16),
                      ),
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    child: Text(
                      msg["text"]!,
                      style: TextStyle(
                        color: isUser
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 15,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Loading indicator while waiting for Gemini
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.teal,
                ),
              ),
            ),

          // BOTTOM MESSAGE INPUT BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      hintText: 'Ask Gemini about your budget...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: _sendMessageToGemini,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.send,
                    color: _isLoading
                        ? Theme.of(context).disabledColor
                        : Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: _isLoading
                      ? null
                      : () => _sendMessageToGemini(_messageController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

TransactionCategory getSmartCategory(String merchantName) {
  final name = merchantName.toLowerCase().trim();

  if (name.contains('zomato') ||
      name.contains('swiggy') ||
      name.contains('restaurant') ||
      name.contains('food') ||
      name.contains('mcdonald') ||
      name.contains('kfc') ||
      name.contains('dominos')) {
    return TransactionCategory(
      name: 'Food',
      icon: Icons.fastfood_rounded,
      color: Colors.orange,
    );
  }

  if (name.contains('starbucks') ||
      name.contains('coffee') ||
      name.contains('cafe') ||
      name.contains('chai')) {
    return TransactionCategory(
      name: 'Café',
      icon: Icons.coffee_rounded,
      color: Colors.brown,
    );
  }

  if (name.contains('uber') ||
      name.contains('ola') ||
      name.contains('auto') ||
      name.contains('metro') ||
      name.contains('petrol') ||
      name.contains('fuel')) {
    return TransactionCategory(
      name: 'Transport',
      icon: Icons.directions_car_rounded,
      color: Colors.blue,
    );
  }

  if (name.contains('netflix') ||
      name.contains('spotify') ||
      name.contains('prime') ||
      name.contains('youtube') ||
      name.contains('hotstar') ||
      name.contains('game')) {
    return TransactionCategory(
      name: 'Entertainment',
      icon: Icons.movie_creation_rounded,
      color: Colors.purple,
    );
  }

  if (name.contains('amazon') ||
      name.contains('flipkart') ||
      name.contains('groceries') ||
      name.contains('supermarket') ||
      name.contains('myntra') ||
      name.contains('mall')) {
    return TransactionCategory(
      name: 'Shopping',
      icon: Icons.shopping_bag_rounded,
      color: Colors.pink,
    );
  }

  return TransactionCategory(
    name: 'Misc',
    icon: Icons.label_rounded,
    color: Colors.blueGrey,
  );
}

class TransactionCategory {
  final String name;
  final IconData icon;
  final Color color;

  TransactionCategory({
    required this.name,
    required this.icon,
    required this.color,
  });
}
