// lib/sync_queue_manager.dart
import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_sync_service.dart';
import 'database_service.dart';

/// In-memory + persisted representation of a single pending sync job.
class PendingSyncJob {
  final String id;
  final String userId;
  final List<CachedTransaction> transactions;
  final DateTime queuedAt;

  PendingSyncJob({
    required this.id,
    required this.userId,
    required this.transactions,
    required this.queuedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'userId': userId,
    'queuedAt': queuedAt.toIso8601String(),
    'transactions': transactions.map((t) => t.toMap()).toList(),
  };

  factory PendingSyncJob.fromMap(Map<String, dynamic> map) {
    final rawTxs = (map['transactions'] as List?) ?? const [];
    final txs = rawTxs
        .whereType<Map>()
        .map((m) => CachedTransaction.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    return PendingSyncJob(
      id: map['id']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      queuedAt:
          DateTime.tryParse(map['queuedAt']?.toString() ?? '') ??
          DateTime.now(),
      transactions: txs,
    );
  }
}

/// Snapshot of the manager's current state — useful for UI badges.
class SyncQueueState {
  final bool isOnline;
  final bool isFlushing;
  final int pendingCount;
  final DateTime? lastSyncAt;
  final String? lastError;

  const SyncQueueState({
    required this.isOnline,
    required this.isFlushing,
    required this.pendingCount,
    this.lastSyncAt,
    this.lastError,
  });

  bool get hasPending => pendingCount > 0;

  String get statusLabel {
    if (isFlushing) return 'Syncing now...';
    if (!isOnline) return 'Sync Pending (Device Offline)';
    if (hasPending) return 'Sync Pending ($pendingCount queued)';
    return 'Up to date';
  }

  SyncQueueState copyWith({
    bool? isOnline,
    bool? isFlushing,
    int? pendingCount,
    DateTime? lastSyncAt,
    String? lastError,
  }) {
    return SyncQueueState(
      isOnline: isOnline ?? this.isOnline,
      isFlushing: isFlushing ?? this.isFlushing,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: lastError,
    );
  }
}

/// Listens to network status, persists pending sync jobs across app
/// restarts, and flushes the queue as soon as connectivity is restored.
class SyncQueueManager {
  static const String _queuePrefsKey = 'pending_sync_jobs_v1';

  final CloudSyncService _cloudSync;
  final Connectivity _connectivity;
  final List<void Function(SyncQueueState)> _listeners = [];

  StreamSubscription<List<ConnectivityResult>>? _connSub;

  SyncQueueState _state = const SyncQueueState(
    isOnline: true,
    isFlushing: false,
    pendingCount: 0,
  );

  SyncQueueState get state => _state;

  SyncQueueManager({CloudSyncService? cloudSync, Connectivity? connectivity})
    : _cloudSync = cloudSync ?? CloudSyncService(),
      _connectivity = connectivity ?? Connectivity();

  /// Begin watching the device's connection state. Safe to call once at app
  /// startup; calling more than once is a no-op.
  Future<void> initialize() async {
    // 1) Restore any jobs persisted from a previous session.
    await _restoreQueueFromDisk();
    _emit(_state.copyWith(pendingCount: _pendingJobs.length));

    // 2) Subscribe to connectivity changes and seed with the current value.
    final initial = await _connectivity.checkConnectivity();
    _updateOnlineStatus(_isOnlineResult(initial));

    _connSub ??= _connectivity.onConnectivityChanged.listen((results) {
      _updateOnlineStatus(_isOnlineResult(results));
    });
  }

  void dispose() {
    _connSub?.cancel();
    _connSub = null;
  }

  /// Subscribe to state changes. Returns an unsubscribe handle.
  void Function() addListener(void Function(SyncQueueState) listener) {
    _listeners.add(listener);
    // Push the current state immediately so UIs can hydrate.
    listener(_state);
    return () => _listeners.remove(listener);
  }

  /// Entry point for "Sync Data Now".
  /// - If online: attempts the sync immediately.
  /// - If offline: queues the batch and surfaces 'Sync Pending'.
  Future<CloudSyncResult> requestSync({
    required List<CachedTransaction> batch,
    required String userId,
  }) async {
    if (batch.isEmpty) {
      return CloudSyncResult.empty();
    }

    if (!_state.isOnline) {
      await _enqueue(
        PendingSyncJob(
          id: _newJobId(),
          userId: userId,
          transactions: batch,
          queuedAt: DateTime.now(),
        ),
      );
      return CloudSyncResult(
        status: CloudSyncStatus.offline,
        message: 'Sync Pending (Device Offline). Will retry automatically.',
        timestamp: DateTime.now(),
      );
    }

    final result = await _runSync(
      PendingSyncJob(
        id: _newJobId(),
        userId: userId,
        transactions: batch,
        queuedAt: DateTime.now(),
      ),
    );

    // If the call itself failed because we lost connectivity mid-flight,
    // queue it and let the listener flush it on the next reconnect.
    if (result.status == CloudSyncStatus.offline) {
      await _enqueue(
        PendingSyncJob(
          id: _newJobId(),
          userId: userId,
          transactions: batch,
          queuedAt: DateTime.now(),
        ),
      );
    }

    return result;
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  final List<PendingSyncJob> _pendingJobs = [];
  bool _flushing = false;

  bool _isOnlineResult(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  void _updateOnlineStatus(bool isOnline) {
    _emit(_state.copyWith(isOnline: isOnline));
    if (isOnline) {
      // Fire-and-forget flush whenever we transition back online.
      unawaited(_flushQueue());
    }
  }

  Future<void> _enqueue(PendingSyncJob job) async {
    _pendingJobs.add(job);
    _emit(_state.copyWith(pendingCount: _pendingJobs.length));
    await _persistQueue();
  }

  Future<void> _flushQueue() async {
    if (_flushing) return;
    if (_pendingJobs.isEmpty) return;
    if (!_state.isOnline) return;

    _flushing = true;
    _emit(_state.copyWith(isFlushing: true));

    try {
      // Make a copy because the list may mutate mid-iteration.
      final snapshot = List<PendingSyncJob>.from(_pendingJobs);
      for (final job in snapshot) {
        if (!_state.isOnline) break;
        final result = await _runSync(job);
        if (result.isSuccess) {
          _pendingJobs.removeWhere((j) => j.id == job.id);
          await _persistQueue();
          _emit(
            _state.copyWith(pendingCount: _pendingJobs.length, lastError: null),
          );
        } else if (result.status == CloudSyncStatus.offline) {
          // Lost the network mid-flush — stop, will resume on next reconnect.
          break;
        } else {
          // Server / auth error — surface but keep the job in the queue so
          // the user can resolve it (e.g. re-auth) and retry.
          _emit(_state.copyWith(lastError: result.message));
          break;
        }
      }
    } finally {
      _flushing = false;
      _emit(_state.copyWith(isFlushing: false));
    }
  }

  Future<CloudSyncResult> _runSync(PendingSyncJob job) async {
    return _cloudSync.pushTransactionBatch(
      job.transactions,
      userId: job.userId,
    );
  }

  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_pendingJobs.map((j) => j.toMap()).toList());
      await prefs.setString(_queuePrefsKey, encoded);
    } catch (e) {
      debugPrint('Persist sync queue error: $e');
    }
  }

  Future<void> _restoreQueueFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_queuePrefsKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _pendingJobs
        ..clear()
        ..addAll(
          decoded.whereType<Map>().map(
            (m) => PendingSyncJob.fromMap(Map<String, dynamic>.from(m)),
          ),
        );
    } catch (e) {
      debugPrint('Restore sync queue error: $e');
    }
  }

  void _emit(SyncQueueState next) {
    _state = next;
    for (final l in List.of(_listeners)) {
      try {
        l(_state);
      } catch (e) {
        debugPrint('Sync queue listener error: $e');
      }
    }
  }

  String _newJobId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_pendingJobs.length}';
}
