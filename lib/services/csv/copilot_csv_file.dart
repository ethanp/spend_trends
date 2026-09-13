import 'dart:io';

/// Local Copilot Money export (gitignored). Replace the file, then re-import.
const copilotTransactionsRelativePath =
    'assets/imports/copilot_transactions.csv';

/// Resolves the gitignored Copilot Money export on disk.
class const CopilotCsvFile({required final String relativePath}) {
  static const local = CopilotCsvFile(
    relativePath: copilotTransactionsRelativePath,
  );

  Future<File> resolve() async {
    final candidates = [
      File(relativePath),
      File('${Directory.current.path}/$relativePath'),
    ];
    for (final candidate in candidates) {
      if (await candidate.exists()) return candidate;
    }
    throw StateError(
      'Missing $relativePath '
      '(gitignored — copy your Copilot export there, then try again).',
    );
  }
}
