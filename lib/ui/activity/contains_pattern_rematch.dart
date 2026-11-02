import 'dart:async';

import 'package:spend_trends/domain/transactions/transaction.dart';
import 'package:flutter/foundation.dart';

/// Debounced live rematch of a contains-pattern against existing transactions.
class ContainsPatternRematch({
  required final Future<List<BankTransaction>> Function(String pattern)
  _fetchMatches,
  required final VoidCallback _notify,
}) {
  Timer? _timer;
  bool rematching = false;
  List<BankTransaction> matches = const [];
  String _activePattern = '';

  void dispose() {
    _timer?.cancel();
  }

  /// Immediate rematch (initial load or explicit refresh).
  Future<void> rematch(String pattern) async {
    _timer?.cancel();
    await _run(pattern.trim());
  }

  /// Debounced rematch while the user types.
  void schedule(String pattern) {
    _timer?.cancel();
    _timer = Timer(
      const Duration(milliseconds: 280),
      () => _run(pattern.trim()),
    );
  }

  Future<void> _run(String pattern) async {
    _activePattern = pattern;
    rematching = true;
    _notify();
    try {
      final nextMatches = pattern.isEmpty
          ? const <BankTransaction>[]
          : await _fetchMatches(pattern);
      if (_activePattern != pattern) return;
      matches = nextMatches;
    } finally {
      if (_activePattern == pattern) {
        rematching = false;
        _notify();
      }
    }
  }
}
