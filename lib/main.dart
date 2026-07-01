import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:universal_html/html.dart' as html;
// Needed to convert your list into a JSON string for storage

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const ProviderScope(child: FinanceApp()));
}

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Finance Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const MainNavigationScreen(),
    );
  }
}

// --- APP SERVICES LAYER (RIVERPOD NOTIFIER) ---

class TransactionNotifier extends Notifier<List<Map<String, dynamic>>> {
  @override
  List<Map<String, dynamic>> build() {
    return [
      {"merchant": "Starbucks Coffee", "amount": 180.00, "date": "Today"},
      {"merchant": "Netflix Subscription", "amount": 649.00, "date": "Yesterday"},
      {"merchant": "Electric Bill", "amount": 2450.00, "date": "24 June"},
      {"merchant": "Zomato Delivery", "amount": 420.00, "date": "22 June"},
      {"merchant": "Petrol Pump", "amount": 1000.00, "date": "21 June"},
    ];
  }

  void addTransaction(String merchant, double amount) {
    state = [
      {"merchant": merchant, "amount": amount, "date": "Just Now"},
      ...state,
    ];
  }
}

final transactionProvider = NotifierProvider<TransactionNotifier, List<Map<String, dynamic>>>(() {
  return TransactionNotifier();
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
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: Colors.teal),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble, color: Colors.teal),
            label: 'AI Chat',
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
  final double totalIncome = 50000.00;
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _voiceWords = "";
  bool isDarkMode = false;
  bool isLocked = true;
  final TextEditingController _pinController = TextEditingController();
  static const String correctPin = "1234";
  String aiCoachInsight =
      "Tap the refresh icon to get custom financial insights from Gemini.";
  bool isAiLoading = false;
  bool isScanLoading = false;
  final Map<String, double> categoryBudgets = {
    'Food': 5000.0,
    'Café': 2000.0,
    'Transport': 3000.0,
    'Entertainment': 4000.0,
    'Shopping': 6000.0,
  };

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _toggleTheme(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = value;
    });
    await prefs.setBool('isDarkMode', value);
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  double _getCategoryTotal(String categoryName) {
    double total = 0.0;
    final transactions = ref.watch(transactionProvider);

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

  List<PieChartSectionData> getShowingSections() {
    final transactions = ref.watch(transactionProvider);
    final Map<String, double> categoryTotals = {};
    double totalExpense = 0;

    for (final tx in transactions) {
      final merchant = tx["merchant"] as String;
      final amount = (tx["amount"] as num).toDouble();
      final cat = getSmartCategory(merchant);

      categoryTotals[cat.name] = (categoryTotals[cat.name] ?? 0) + amount;
      totalExpense += amount;
    }

    if (totalExpense == 0) {
      return [
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

    return categoryTotals.entries.map((entry) {
      final catName = entry.key;
      final amount = entry.value;

      Color sectionColor = Colors.blueGrey;
      if (catName == 'Food') sectionColor = Colors.orange;
      if (catName == 'Caf\u00e9') sectionColor = Colors.brown;
      if (catName == 'Transport') sectionColor = Colors.blue;
      if (catName == 'Entertainment') sectionColor = Colors.purple;
      if (catName == 'Shopping') sectionColor = Colors.pink;

      final percentage = (amount / totalExpense) * 100;

      return PieChartSectionData(
        color: sectionColor,
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

  Widget _buildBudgetProgressBar(String category, double budget) {
    final spent = _getCategoryTotal(category);
    final percent = budget > 0 ? (spent / budget) : 0.0;
    final visualPercent = percent > 1.0 ? 1.0 : percent;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;

    Color progressColor = Colors.teal;
    if (percent >= 0.85) {
      progressColor = Colors.redAccent;
    } else if (percent >= 0.50) {
      progressColor = Colors.orangeAccent;
    }

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
                "₹${spent.toStringAsFixed(0)} / ₹${budget.toStringAsFixed(0)} (${(percent * 100).toStringAsFixed(0)}%)",
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
      final dataReport = StringBuffer();

      categoryBudgets.forEach((category, budget) {
        final spent = _getCategoryTotal(category);
        dataReport.writeln(
          "- $category: Spent ₹$spent out of a budget of ₹$budget.",
        );
      });

      for (final tx in transactions.take(5)) {
        dataReport.writeln(
          "- ${tx['merchant']}: ₹${tx['amount']} on ${tx['date']?.toString().split(' ')[0]}",
        );
      }

      final prompt = """
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
                {"text": prompt}
              ]
            }
          ]
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

  Widget _buildAICoachCard(Color cardColor, Color textColor) {
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
                ? [Colors.teal[900]!, Colors.grey[850]!]
                : [Colors.teal[50]!, Colors.white],
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
                      color: isDarkMode ? Colors.tealAccent : Colors.teal,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "AI Financial Advisor",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                isAiLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.teal,
                        ),
                      )
                    : IconButton(
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.teal,
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
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[800],
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
                    "Analyze this receipt image. Extract the merchant name, the total amount spent, and the category (e.g., Food, Cafe, Utilities, Transport, Entertainment). Respond ONLY with a valid, raw JSON object exactly like this: {\"merchant\": \"Name\", \"amount\": 0.0, \"category\": \"Category\"}. Do not wrap it in markdown code blocks."
              },
              {
                "inlineData": {
                  "mimeType": "image/jpeg",
                  "data": base64Image,
                }
              }
            ]
          }
        ]
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
        final amount = extractedData['amount'];

        ref.read(transactionProvider.notifier).addTransaction(
              extractedData['merchant']?.toString() ?? 'Unknown Merchant',
              amount is num ? amount.toDouble() : 0.0,
            );

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

  void _exportToCSV() {
    final transactions = ref.read(transactionProvider);

    // 1. Build the CSV contents as plain text strings manually
    final StringBuffer csvBuilder = StringBuffer();

    // Add headers
    csvBuilder.writeln("Date,Merchant/Description,Category,Amount (INR)");

    // 2. Loop through your items and map them down line by line
    for (final tx in transactions) {
      // Safely extract values from your transaction object or map
      final String date = tx['date']?.toString().split(' ')[0] ?? '';
      final String merchant =
          tx['merchant']?.toString().replaceAll(',', '') ?? 'Unknown';

      // Get the category name using your existing helper function
      final String categoryName = getSmartCategory(merchant).name;
      final String amount = (tx['amount'] ?? 0).toString();

      // Write a clean, comma-separated row line
      csvBuilder.writeln("$date,$merchant,$categoryName,$amount");
    }

    // 3. Trigger the browser's download window natively using universal_html
    final blob = html.Blob([csvBuilder.toString()], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..setAttribute("download",
          "finance_report_${DateTime.now().millisecondsSinceEpoch}.csv")
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  void _exportToPDF() {
    final transactions = ref.read(transactionProvider);
    final totalSpent = transactions.fold<double>(
      0,
      (sum, item) => sum + (item['amount'] as num).toDouble(),
    );

    final tableRows = transactions.map((tx) {
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
    }).join('');

    final htmlContent = '''
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

  void _showAddTransactionDialog() {
    final merchantController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: merchantController,
              decoration: const InputDecoration(labelText: 'Merchant Name'),
            ),
            TextField(
              controller: amountController,
              decoration: const InputDecoration(labelText: 'Amount (₹)'),
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
              if (merchantController.text.isNotEmpty && amountController.text.isNotEmpty) {
                final amt = double.tryParse(amountController.text) ?? 0.0;
                ref.read(transactionProvider.notifier).addTransaction(merchantController.text, amt);
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
      parsedMerchant = parsedMerchant.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1);
      }).join(' ');
    }

    if (parsedAmount != null) {
      ref.read(transactionProvider.notifier).addTransaction(
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

  Widget _buildLockScreen() {
    return Scaffold(
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.grey[100],
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 80,
                color: isDarkMode ? Colors.tealAccent : Colors.teal,
              ),
              const SizedBox(height: 16),
              Text(
                "Dashboard Locked",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Enter PIN to view your balances",
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    counterText: "",
                    filled: true,
                    fillColor: isDarkMode ? Colors.grey[800] : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (val) {
                    if (val == correctPin) {
                      setState(() {
                        isLocked = false;
                      });
                      _pinController.clear();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLocked) {
      return _buildLockScreen();
    }

    final transactions = ref.watch(transactionProvider);
    double totalExpenses = transactions.fold(0.0, (sum, item) => sum + item["amount"]);
    double currentBalance = totalIncome - totalExpenses;
    final cardColor = isDarkMode ? Colors.grey[850]! : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.grey[900],
      ),
      home: Scaffold(
      appBar: AppBar(
        title: const Text('AI Finance Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isDarkMode ? Colors.teal[800] : Colors.teal,
        centerTitle: true,
        actions: [
          Icon(isDarkMode ? Icons.dark_mode : Icons.light_mode),
          Switch(
            value: isDarkMode,
            onChanged: _toggleTheme,
            activeThumbColor: Colors.tealAccent,
          ),
          IconButton(
            icon: const Icon(Icons.power_settings_new),
            tooltip: 'Lock Dashboard',
            onPressed: () => setState(() => isLocked = true),
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
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Balance', style: TextStyle(color: Colors.white70, fontSize: 16)),
                    IconButton(
                      icon: Icon(
                        _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: _isListening ? Colors.red : Colors.white,
                      ),
                      onPressed: _listen,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${currentBalance.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          child: const Icon(Icons.arrow_downward, color: Colors.greenAccent),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Income', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            Text('₹${totalIncome.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          child: const Icon(Icons.arrow_upward, color: Colors.redAccent),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Expenses', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            Text('₹${totalExpenses.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ],
                    ),
                  ],
                )
              ],
            ),
          ),
          _buildAICoachCard(cardColor, textColor),
          const SizedBox(height: 8),
          Container(
            height: 180,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 35,
                      sections: getShowingSections(),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLegendItem(Colors.orange, 'Food'),
                      _buildLegendItem(Colors.brown, 'Caf\u00e9'),
                      _buildLegendItem(Colors.blue, 'Transport'),
                      _buildLegendItem(Colors.purple, 'Entertainment'),
                      _buildLegendItem(Colors.pink, 'Shopping'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.all(16.0),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
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
                    return _buildBudgetProgressBar(entry.key, entry.value);
                  }),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                      icon: const Icon(Icons.table_view_rounded, color: Colors.green),
                      tooltip: 'Export CSV Spreadsheet',
                      onPressed: _exportToCSV,
                    ),
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent),
                      tooltip: 'Print Summary PDF',
                      onPressed: _exportToPDF,
                    ),
                  ],
                ),
              ],
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: transactions.length,
            itemBuilder: (context, index) {
                final tx = transactions[index];
                final smartCategory = getSmartCategory(tx["merchant"] as String);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: smartCategory.color.withValues(alpha: 0.15),
                      child: Icon(smartCategory.icon, color: smartCategory.color),
                    ),
                    title: Text(
                      tx["merchant"],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                      '- ₹${tx["amount"].toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.redAccent),
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
            heroTag: 'addTransaction',
            onPressed: _showAddTransactionDialog,
            backgroundColor: Colors.teal,
            child: const Icon(Icons.add, color: Colors.white),
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
      "text": "Hello! I am your AI Finance Assistant. Ask me anything about your expenses or dynamic balance!"
    }
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

      final prompt = """
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
                {"text": prompt}
              ]
            }
          ]
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

      double totalExpenses = currentTransactions.fold(0.0, (sum, item) => sum + item["amount"]);
      double dynamicBalance = 50000.00 - totalExpenses;

      String transactionContext = "You are a helpful financial assistant app. Here is the user's current live transaction data:\n";
      transactionContext += "Total Income base: ₹50,000.00\n";
      transactionContext += "Current Calculated Balance: ₹${dynamicBalance.toStringAsFixed(2)}\n";
      transactionContext += "Total Expenses: ₹${totalExpenses.toStringAsFixed(2)}\n\n";
      transactionContext += "Transaction Records:\n";
      
      for (var tx in currentTransactions) {
        transactionContext += "- ${tx['date']}: ${tx['merchant']} for ₹${tx['amount']}\n";
      }
      
      transactionContext += "\nAnswer the user's question accurately using ONLY the structured financial data provided above. Be concise and conversational. User question: $query";

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": transactionContext}
              ]
            }
          ]
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
            "text": "Chat Error: ${response.statusCode}\nDetails: ${response.body}"
          });
        });
      }
    } catch (e) {
      setState(() {
        _messages.add({
          "sender": "ai",
          "text": "Error connecting to Gemini API. Details: $e"
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
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Gemini Financial Assistant', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal.shade100,
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
                  "text": "Hello! I am your AI Finance Assistant. Ask me anything about your expenses or dynamic balance!"
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
                style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
              ),
            ),
          )
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
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.teal : Colors.grey.shade200,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
                        bottomRight: isUser ? Radius.zero : const Radius.circular(16),
                      ),
                    ),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    child: Text(
                      msg["text"]!,
                      style: TextStyle(
                        color: isUser ? Colors.white : Colors.black87,
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
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.teal),
              ),
            ),

          // BOTTOM MESSAGE INPUT BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                )
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
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: _sendMessageToGemini,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send, color: _isLoading ? Colors.grey : Colors.teal),
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
