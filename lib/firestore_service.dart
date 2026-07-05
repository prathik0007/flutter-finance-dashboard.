import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TransactionModel {
  final String id;
  final String merchant;
  final double amount;
  final String category;
  final DateTime date;
  final String userId;

  TransactionModel({
    required this.id,
    required this.merchant,
    required this.amount,
    required this.category,
    required this.date,
    required this.userId,
  });

  factory TransactionModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data();
    return TransactionModel(
      id: snapshot.id,
      merchant: data?['merchant'] ?? '',
      amount: (data?['amount'] as num?)?.toDouble() ?? 0.0,
      category: data?['category'] ?? 'Misc',
      date: (data?['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      userId: data?['userId'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      "merchant": merchant,
      "amount": amount,
      "category": category,
      "date": Timestamp.fromDate(date),
      "userId": userId,
    };
  }
}

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collection reference with type safety using withConverter
  CollectionReference<TransactionModel> get _transactionsRef =>
      _db.collection('transactions').withConverter<TransactionModel>(
            fromFirestore: TransactionModel.fromFirestore,
            toFirestore: (tx, _) => tx.toFirestore(),
          );

  // Function to add a new transaction tied to the current user
  Future<void> addTransaction(String merchant, double amount, String category) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User must be logged in to save data.");

    final newTx = TransactionModel(
      id: '', // Firestore will generate this
      merchant: merchant,
      amount: amount,
      category: category,
      date: DateTime.now(),
      userId: user.uid,
    );

    await _transactionsRef.add(newTx);
  }

  // Stream of transactions for the currently logged-in user
  Stream<List<TransactionModel>> getTransactionsStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _transactionsRef
        .where('userId', isEqualTo: user.uid)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  // --- USER PROFILE / INCOME METHODS ---

  Future<void> updateMonthlyIncome(double income) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _db.collection('users').doc(user.uid).set({
      'monthlyIncome': income,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<double?> getMonthlyIncomeStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(null);

    return _db.collection('users').doc(user.uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data();
      return (data?['monthlyIncome'] as num?)?.toDouble();
    });
  }
}
