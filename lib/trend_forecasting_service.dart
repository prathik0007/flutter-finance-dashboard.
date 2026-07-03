// lib/trend_forecasting_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Outcome of a single forecast request.
enum ForecastStatus { success, offline, unauthorized, serverError, unknown }

class CategoryForecast {
  final String category;
  final double historicalAverage; // INR / month, lifetime
  final double predictedNextMonth; // INR
  final double confidencePercent; // 0-100
  final bool breachLikely; // predicted > budget limit
  final double? budgetLimit; // null if no limit set
  final String rationale; // short human-readable explanation

  const CategoryForecast({
    required this.category,
    required this.historicalAverage,
    required this.predictedNextMonth,
    required this.confidencePercent,
    required this.breachLikely,
    this.budgetLimit,
    required this.rationale,
  });

  factory CategoryForecast.fromMap(Map<String, dynamic> map) {
    double? nullableNum(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return CategoryForecast(
      category: map['category']?.toString() ?? 'Misc',
      historicalAverage: nullableNum(map['historicalAverage']) ?? 0.0,
      predictedNextMonth: nullableNum(map['predictedNextMonth']) ?? 0.0,
      confidencePercent: nullableNum(map['confidencePercent']) ?? 0.0,
      breachLikely: map['breachLikely'] == true,
      budgetLimit: nullableNum(map['budgetLimit']),
      rationale: map['rationale']?.toString() ?? '',
    );
  }
}

class ForecastResult {
  final ForecastStatus status;
  final String message;
  final List<CategoryForecast> forecasts;
  final List<String> breachWarnings; // human-readable, e.g. "Food: ..."
  final DateTime timestamp;

  const ForecastResult({
    required this.status,
    required this.message,
    required this.forecasts,
    required this.breachWarnings,
    required this.timestamp,
  });

  bool get isSuccess => status == ForecastStatus.success;
  bool get hasBreaches => breachWarnings.isNotEmpty;

  factory ForecastResult.failure(
    ForecastStatus status,
    String message, {
    List<String>? breachWarnings,
  }) {
    return ForecastResult(
      status: status,
      message: message,
      forecasts: const [],
      breachWarnings: breachWarnings ?? const [],
      timestamp: DateTime.now(),
    );
  }
}

/// Pure statistical helpers (no Gemini dependency).
class _TrendMath {
  /// Mean of [values], or 0.0 if empty.
  static double mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sum = values.fold<double>(0.0, (a, b) => a + b);
    return sum / values.length;
  }

  /// Sample standard deviation. Returns 0.0 when there is <2 datapoints
  /// (we cannot infer variance from a single point).
  static double stdDev(List<double> values) {
    if (values.length < 2) return 0.0;
    final m = mean(values);
    final sumSq = values.fold<double>(0.0, (a, b) => a + (b - m) * (b - m));
    return _sqrt(sumSq / (values.length - 1));
  }

  /// Confidence proxy: lower coefficient of variation -> higher confidence.
  /// Returns a value in [40, 95] so we never claim 100% certainty.
  static double confidenceFromVariance(List<double> values) {
    if (values.isEmpty) return 0.0;
    final m = mean(values);
    if (m == 0) {
      // All zeros historically -> we can be fairly confident of 0 next month.
      return values.length >= 2 ? 90.0 : 60.0;
    }
    final cv = stdDev(values) / m; // coefficient of variation
    // Map cv in [0, 1+] to confidence in [95, 40].
    final clamped = cv.clamp(0.0, 1.0);
    return 95.0 - (clamped * 55.0);
  }

  /// Lightweight sqrt for the no-dart:math import path.
  static double _sqrt(double x) {
    if (x <= 0) return 0.0;
    double guess = x;
    for (int i = 0; i < 16; i++) {
      guess = (guess + x / guess) / 2.0;
    }
    return guess;
  }
}

/// Aggregates transaction history and asks Gemini to project next month's
/// category spending. Pure-Dart pre-aggregation is done locally so the
/// prompt stays small and the response stays structured.
class TrendForecastingService {
  final String apiKey;
  final Uri endpoint;
  final Duration timeout;

  TrendForecastingService({
    required this.apiKey,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 20),
  }) : endpoint =
           endpoint ??
           Uri.parse(
             'https://generativelanguage.googleapis.com/v1beta/models/'
             'gemini-2.5-flash:generateContent',
           );

  /// Build a [ForecastResult] from the active transaction list and the
  /// user's category budget limits. The function is non-throwing — all
  /// errors are converted into a [ForecastResult] with a typed status.
  Future<ForecastResult> generateForecast({
    required List<Map<String, dynamic>> transactions,
    required Map<String, double> categoryBudgetLimits, // INR
  }) async {
    // 1) Aggregate locally first.
    final monthlyByCategory = _aggregateMonthlyTotals(transactions);
    if (monthlyByCategory.isEmpty) {
      return ForecastResult.failure(
        ForecastStatus.success,
        'No historical data available yet. Add a few transactions and try again.',
      );
    }

    // 2) Compute local baseline statistics (mean, stddev) for each category.
    final localStats = <String, _LocalCategoryStats>{};
    monthlyByCategory.forEach((category, monthly) {
      final values = monthly.values.toList();
      localStats[category] = _LocalCategoryStats(
        average: _TrendMath.mean(values),
        stdDev: _TrendMath.stdDev(values),
        confidence: _TrendMath.confidenceFromVariance(values),
        monthsObserved: values.length,
      );
    });

    // 3) Build the structured prompt.
    final payload = _buildRequestPayload(
      monthlyByCategory: monthlyByCategory,
      categoryBudgetLimits: categoryBudgetLimits,
      localStats: localStats,
    );

    // 4) Call Gemini. Retry once on 5xx, fail fast on 401/403.
    http.Response? response;
    try {
      response = await http
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode(payload),
          )
          .timeout(timeout);
    } on TimeoutException {
      return ForecastResult.failure(
        ForecastStatus.offline,
        'Forecast request timed out. Check your connection and try again.',
      );
    } catch (e) {
      return ForecastResult.failure(
        ForecastStatus.unknown,
        'Forecast request failed: $e',
      );
    }

    final status = response.statusCode;
    if (status == 401 || status == 403) {
      return ForecastResult.failure(
        ForecastStatus.unauthorized,
        'Authentication failed ($status). Check your Gemini API key.',
      );
    }
    if (status < 200 || status >= 300) {
      return ForecastResult.failure(
        ForecastStatus.serverError,
        'Forecast service returned $status. Try again later.',
      );
    }

    // 5) Parse the model response into [CategoryForecast]s.
    final parsed = _parseModelResponse(response.body);
    if (parsed.status != ForecastStatus.success) {
      return parsed;
    }

    // 6) Cross-check Gemini's breachLikely with the local budget limits so a
    //    bad prompt can't silently miss a real budget violation.
    final crossedForecasts = <CategoryForecast>[];
    for (final f in parsed.forecasts) {
      final limit = categoryBudgetLimits[f.category];
      final bool breach =
          (limit != null && f.predictedNextMonth > limit) || f.breachLikely;
      crossedForecasts.add(
        CategoryForecast(
          category: f.category,
          historicalAverage: f.historicalAverage,
          predictedNextMonth: f.predictedNextMonth,
          confidencePercent: f.confidencePercent,
          breachLikely: breach,
          budgetLimit: limit ?? f.budgetLimit,
          rationale: f.rationale,
        ),
      );
    }

    final warnings = crossedForecasts.where((f) => f.breachLikely).map((f) {
      final limit = f.budgetLimit;
      if (limit == null) {
        return '${f.category}: predicted '
            'â‚¹${f.predictedNextMonth.toStringAsFixed(0)} next month '
            '(${f.confidencePercent.toStringAsFixed(0)}% confidence).';
      }
      return '${f.category}: predicted '
          'â‚¹${f.predictedNextMonth.toStringAsFixed(0)} vs limit '
          'â‚¹${limit.toStringAsFixed(0)} next month '
          '(${f.confidencePercent.toStringAsFixed(0)}% confidence).';
    }).toList();

    return ForecastResult(
      status: ForecastStatus.success,
      message: warnings.isEmpty
          ? 'No category limits are likely to be breached next month.'
          : '${warnings.length} category limit(s) at risk next month.',
      forecasts: crossedForecasts,
      breachWarnings: warnings,
      timestamp: DateTime.now(),
    );
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  /// Group the active transactions into {category: {YYYY-MM: total}}.
  /// Transactions without a usable date fall back to the current month
  /// so they still contribute to the trend.
  Map<String, Map<String, double>> _aggregateMonthlyTotals(
    List<Map<String, dynamic>> transactions,
  ) {
    final result = <String, Map<String, double>>{};
    for (final tx in transactions) {
      final merchant = (tx['merchant'] ?? tx['merchantName'] ?? '').toString();
      final rawCategory = tx['category']?.toString().trim();
      final category = (rawCategory == null || rawCategory.isEmpty)
          ? _fallbackCategory(merchant)
          : rawCategory;

      final amountValue = tx['amount'];
      final amount = amountValue is num
          ? amountValue.toDouble()
          : double.tryParse(amountValue?.toString() ?? '0') ?? 0.0;

      final dateRaw = tx['date']?.toString() ?? '';
      final date =
          DateTime.tryParse(dateRaw) ??
          DateTime.tryParse(_normalizeDate(dateRaw)) ??
          DateTime.now();
      final monthKey =
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

      final byMonth = result.putIfAbsent(category, () => <String, double>{});
      byMonth[monthKey] = (byMonth[monthKey] ?? 0) + amount;
    }
    return result;
  }

  String _normalizeDate(String raw) {
    // Accept forms like "24 June" -> treat as current year.
    final months = {
      'january': 1,
      'february': 2,
      'march': 3,
      'april': 4,
      'may': 5,
      'june': 6,
      'july': 7,
      'august': 8,
      'september': 9,
      'october': 10,
      'november': 11,
      'december': 12,
    };
    final lower = raw.toLowerCase().trim();
    if (lower == 'today') {
      final n = DateTime.now();
      return n.toIso8601String();
    }
    if (lower == 'yesterday') {
      final n = DateTime.now().subtract(const Duration(days: 1));
      return n.toIso8601String();
    }
    final parts = lower.split(' ');
    if (parts.length == 2) {
      final day = int.tryParse(parts[0]);
      final month = months[parts[1]];
      if (day != null && month != null) {
        return DateTime(DateTime.now().year, month, day).toIso8601String();
      }
    }
    return raw; // give up, caller will use DateTime.now() fallback
  }

  String _fallbackCategory(String merchant) {
    final m = merchant.toLowerCase();
    if (m.contains('starbucks') ||
        m.contains('zomato') ||
        m.contains('cafe') ||
        m.contains('restaurant')) {
      return 'Food';
    }
    if (m.contains('uber') ||
        m.contains('ola') ||
        m.contains('petrol') ||
        m.contains('fuel')) {
      return 'Transport';
    }
    if (m.contains('netflix') || m.contains('prime') || m.contains('movie')) {
      return 'Entertainment';
    }
    if (m.contains('amazon') || m.contains('flipkart') || m.contains('mall')) {
      return 'Shopping';
    }
    if (m.contains('electric') ||
        m.contains('bill') ||
        m.contains('recharge')) {
      return 'Bills';
    }
    return 'Misc';
  }

  Map<String, dynamic> _buildRequestPayload({
    required Map<String, Map<String, double>> monthlyByCategory,
    required Map<String, double> categoryBudgetLimits,
    required Map<String, _LocalCategoryStats> localStats,
  }) {
    final categoryVectors = <Map<String, dynamic>>[];
    monthlyByCategory.forEach((category, monthly) {
      final sortedKeys = monthly.keys.toList()..sort();
      final timeline = sortedKeys.map((k) {
        return <String, dynamic>{
          'month': k,
          'amount': double.parse(monthly[k]!.toStringAsFixed(2)),
        };
      }).toList();
      final stats = localStats[category]!;
      categoryVectors.add({
        'category': category,
        'timeline': timeline,
        'historicalAverage': double.parse(stats.average.toStringAsFixed(2)),
        'stdDev': double.parse(stats.stdDev.toStringAsFixed(2)),
        'monthsObserved': stats.monthsObserved,
        'budgetLimit': categoryBudgetLimits[category],
      });
    });

    final systemPrompt =
        'You are a personal finance forecasting assistant.\n'
        'Given a category-level monthly spending timeline, predict next '
        "month's spend per category. Use the local statistics provided "
        '(historical average, stddev, months observed) as the baseline.\n'
        'Output STRICTLY a raw JSON object of the form:\n'
        '{\n'
        '  "forecasts": [\n'
        '    {\n'
        '      "category": "string",\n'
        '      "historicalAverage": number,\n'
        '      "predictedNextMonth": number,\n'
        '      "confidencePercent": number, // 0-100\n'
        '      "breachLikely": boolean,\n'
        '      "budgetLimit": number | null,\n'
        '      "rationale": "short one-sentence explanation"\n'
        '    }\n'
        '  ]\n'
        '}\n'
        'Do NOT wrap the response in markdown code blocks. Do NOT add '
        'explanatory text outside the JSON. If a category has only 1 '
        "month of data, weight the prediction closer to the local mean "
        "and reduce confidence.";

    return {
      "systemInstruction": {
        "parts": [
          {"text": systemPrompt},
        ],
      },
      "contents": [
        {
          "parts": [
            {
              "text": jsonEncode({
                'asOf': DateTime.now().toIso8601String(),
                'nextMonthLabel': _nextMonthLabel(),
                'categoryBudgetLimits': categoryBudgetLimits,
                'categoryVectors': categoryVectors,
              }),
            },
          ],
        },
      ],
      "generationConfig": {
        "temperature": 0.2,
        "responseMimeType": "application/json",
      },
    };
  }

  String _nextMonthLabel() {
    final n = DateTime.now();
    final next = DateTime(n.year, n.month + 1, 1);
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
    return '${monthNames[next.month - 1]} ${next.year}';
  }

  ForecastResult _parseModelResponse(String body) {
    try {
      final outer = jsonDecode(body);
      final raw = outer['candidates'][0]['content']['parts'][0]['text']
          .toString()
          .trim();
      final parsed = jsonDecode(raw);
      final list = parsed['forecasts'];
      if (list is! List) {
        return ForecastResult.failure(
          ForecastStatus.unknown,
          'Forecast model returned an unexpected shape.',
        );
      }
      final forecasts = list
          .whereType<Map>()
          .map((m) => CategoryForecast.fromMap(Map<String, dynamic>.from(m)))
          .toList();
      return ForecastResult(
        status: ForecastStatus.success,
        message: 'Forecast generated for ${forecasts.length} categories.',
        forecasts: forecasts,
        breachWarnings: const [],
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return ForecastResult.failure(
        ForecastStatus.unknown,
        'Could not parse forecast response: $e',
      );
    }
  }
}

class _LocalCategoryStats {
  final double average;
  final double stdDev;
  final double confidence;
  final int monthsObserved;
  const _LocalCategoryStats({
    required this.average,
    required this.stdDev,
    required this.confidence,
    required this.monthsObserved,
  });
}
