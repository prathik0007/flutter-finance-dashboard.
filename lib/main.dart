import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
// Needed to convert your list into a JSON string for storage

void main() {
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

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionProvider);
    double totalExpenses = transactions.fold(0.0, (sum, item) => sum + item["amount"]);
    double currentBalance = totalIncome - totalExpenses;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('AI Finance Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal.shade100,
        centerTitle: true,
      ),
      body: Column(
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
                const Text('Total Balance', style: TextStyle(color: Colors.white70, fontSize: 16)),
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Recent Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
            ),
          ),
          Expanded(
            child: ListView.builder(
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTransactionDialog,
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add, color: Colors.white),
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
  final String _geminiApiKey = "AQ.Ab8RN6INTw-7f7iBtfGlu-JCEfv_YKHSbYnyqKPAEo5H8t7raA";

  final List<Map<String, String>> _messages = [
    {
      "sender": "ai",
      "text": "Hello! I am your AI Finance Assistant. Ask me anything about your expenses or dynamic balance!"
    }
  ];

  // 2. The New Asynchronous Gemini Send Message Function
  void _sendMessage() async {
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
      final model = GenerativeModel(
        model: 'models/gemini-3-flash-preview', // Updated to match your AI Studio panel
        apiKey: _geminiApiKey,
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

      final content = [Content.text(transactionContext)];
      final response = await model.generateContent(content);

      setState(() {
        _messages.add({
          "sender": "ai",
          "text": response.text ?? "I processed that, but couldn't formulate a text response."
        });
      });
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
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send, color: _isLoading ? Colors.grey : Colors.teal),
                  onPressed: _sendMessage,
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
