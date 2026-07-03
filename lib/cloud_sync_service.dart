// lib/cloud_sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'database_service.dart';

/// Outcome of a sync attempt. Surfaced back to the UI for snackbars/logs.
enum CloudSyncStatus { success, offline, unauthorized, serverError, unknown }

class CloudSyncResult {
  final CloudSyncStatus status;
  final String message;
  final int? httpStatusCode;
  final DateTime timestamp;

  const CloudSyncResult({
    required this.status,
    required this.message,
    this.httpStatusCode,
    required this.timestamp,
  });

  /// Convenience constructor for the "nothing to do" case where we still
  /// want a real timestamp and a non-const result.
  factory CloudSyncResult.empty() {
    return CloudSyncResult(
      status: CloudSyncStatus.success,
      message: 'Nothing to sync - local cache is empty.',
      timestamp: DateTime.now(),
    );
  }

  bool get isSuccess => status == CloudSyncStatus.success;

  factory CloudSyncResult.fromException(Object e) {
    return CloudSyncResult(
      status: CloudSyncStatus.unknown,
      message: 'Sync failed: $e',
      timestamp: DateTime.now(),
    );
  }
}

/// Lightweight client that pushes the locally-cached transaction batch
/// to a backend database provider. The actual endpoint is injected so the
/// app can be pointed at staging/production without code changes.
class CloudSyncService {
  /// HTTPS endpoint that accepts the transaction batch payload.
  final Uri endpoint;

  /// Bearer token (or session JWT) used to authenticate the upload.
  final String authToken;

  /// Per-request timeout.
  final Duration timeout;

  /// How many times to retry on transient failure before giving up.
  final int maxRetries;

  CloudSyncService({
    Uri? endpoint,
    this.authToken = '',
    this.timeout = const Duration(seconds: 15),
    this.maxRetries = 2,
  }) : endpoint =
           endpoint ??
           Uri.parse('https://api.your-backend.example.com/v1/sync');

  factory CloudSyncService.withEndpoint(
    String url, {
    String authToken = '',
    Duration timeout = const Duration(seconds: 15),
    int maxRetries = 2,
  }) {
    return CloudSyncService(
      endpoint: Uri.parse(url),
      authToken: authToken,
      timeout: timeout,
      maxRetries: maxRetries,
    );
  }

  /// Pushes the provided [batch] up to the backend.
  /// Returns a [CloudSyncResult] describing the outcome - never throws.
  Future<CloudSyncResult> pushTransactionBatch(
    List<CachedTransaction> batch, {
    required String userId,
  }) async {
    if (batch.isEmpty) {
      return CloudSyncResult.empty();
    }

    final payload = {
      'userId': userId,
      'syncedAt': DateTime.now().toUtc().toIso8601String(),
      'device': 'flutter-mobile',
      'version': 1,
      'transactions': batch.map((tx) => tx.toMap()).toList(),
    };

    int attempt = 0;
    while (attempt <= maxRetries) {
      attempt += 1;
      try {
        final response = await http
            .post(
              endpoint,
              headers: {
                'Content-Type': 'application/json; charset=utf-8',
                'Accept': 'application/json',
                if (authToken.isNotEmpty) 'Authorization': 'Bearer $authToken',
              },
              body: jsonEncode(payload),
            )
            .timeout(timeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return CloudSyncResult(
            status: CloudSyncStatus.success,
            message: 'Synced ${batch.length} transactions successfully.',
            httpStatusCode: response.statusCode,
            timestamp: DateTime.now(),
          );
        }

        if (response.statusCode == 401 || response.statusCode == 403) {
          return CloudSyncResult(
            status: CloudSyncStatus.unauthorized,
            message:
                'Authentication failed (${response.statusCode}). Please sign in again.',
            httpStatusCode: response.statusCode,
            timestamp: DateTime.now(),
          );
        }

        if (response.statusCode >= 500 && attempt <= maxRetries) {
          await _backoff(attempt);
          continue;
        }

        return CloudSyncResult(
          status: CloudSyncStatus.serverError,
          message:
              'Server rejected the sync (${response.statusCode}). Try again later.',
          httpStatusCode: response.statusCode,
          timestamp: DateTime.now(),
        );
      } on TimeoutException {
        if (attempt <= maxRetries) {
          await _backoff(attempt);
          continue;
        }
        return CloudSyncResult(
          status: CloudSyncStatus.offline,
          message: 'Sync timed out. Check your network connection.',
          timestamp: DateTime.now(),
        );
      } catch (e) {
        if (attempt <= maxRetries) {
          await _backoff(attempt);
          continue;
        }
        return CloudSyncResult.fromException(e);
      }
    }

    return CloudSyncResult(
      status: CloudSyncStatus.unknown,
      message: 'Sync failed after $maxRetries retries.',
      timestamp: DateTime.now(),
    );
  }

  Future<void> _backoff(int attempt) async {
    final delay = Duration(seconds: 1 << (attempt - 1));
    await Future.delayed(delay);
  }
}
