class const CopilotImportResult({
  required final int transactionCount,
  required final int accountCount,
  required final int skippedRows,
  required final int alreadyPresentCount,
  final int notesFilledCount = 0,

  /// CSV rows skipped because a linked SimpleFIN charge already exists.
  final int simplefinMatchSkipCount = 0,
  final bool cancelled = false,
});

class const CopilotImportProgress({
  required final int completed,
  required final int total,
}) {
  double get fraction => total <= 0 ? 0 : completed / total;
}

/// Cooperative cancel flag for a single Copilot CSV import run.
class CopilotImportCancellation() {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class CopilotImportCancelledException() implements Exception {
  @override
  String toString() => 'Copilot import cancelled.';
}
