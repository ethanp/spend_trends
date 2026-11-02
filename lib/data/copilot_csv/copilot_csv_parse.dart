import 'package:ethan_utils/ethan_utils.dart';

import 'dart:convert';

import 'package:csv/csv.dart';

/// Parsed Copilot Money CSV table (header map + data rows).
class const CopilotCsvTable({
  required final CopilotCsvColumns columns,
  required final List<List<dynamic>> dataRows,
}) {
  int get dataRowCount => dataRows.length;

  static CopilotCsvTable parse(String csvText) {
    final rows = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(csvText);
    if (rows.length < 2) {
      throw StateError('Copilot CSV is empty.');
    }

    final headers = rows.first
        .map((cell) => cell.toString().trim().toLowerCase())
        .toList();
    return CopilotCsvTable(
      columns: CopilotCsvColumns.fromHeaders(headers),
      dataRows: rows.sublist(1),
    );
  }
}

class const CopilotCsvColumns({
  required final int date,
  required final int name,
  required final int amount,
  required final int status,
  required final int category,
  required final int account,
  required final int accountMask,
  required final int note,
  required final int type,
  required final int excluded,
  required final int recurring,
}) {
  int get minimumWidth =>
      [
        date,
        name,
        amount,
        status,
        category,
        account,
        accountMask,
        note,
        type,
        excluded,
        recurring,
      ].reduce((left, right) => left > right ? left : right) +
      1;

  factory fromHeaders(List<String> headers) {
    int require(String header) {
      final index = headers.indexOf(header);
      if (index < 0) {
        throw StateError('Copilot CSV missing "$header" column.');
      }
      return index;
    }

    return CopilotCsvColumns(
      date: require('date'),
      name: require('name'),
      amount: require('amount'),
      status: require('status'),
      category: require('category'),
      account: require('account'),
      accountMask: require('account mask'),
      note: require('note'),
      type: require('type'),
      excluded: require('excluded'),
      recurring: require('recurring'),
    );
  }
}

/// One validated Copilot CSV data row.
class const ParsedCopilotRow({
  required final String dateText,
  required final String name,
  required final String amountText,
  required final String accountName,
  required final String accountMask,
  required final String status,
  required final String categoryText,
  required final String? note,
  required final String? transactionType,
  required final bool excluded,
  required final String? recurringSeries,
  required final String externalId,
  required final DateTime postedAt,
  required final int amountCents,
  required final bool pending,
}) {
  String get accountKey => '$accountName|$accountMask';

  static ParsedCopilotRow? tryParse(
    List<dynamic> row,
    CopilotCsvColumns columns,
  ) {
    if (row.length < columns.minimumWidth) return null;

    final dateText = _cell(row, columns.date).trim();
    final name = _cell(row, columns.name).trim();
    final amountText = _cell(row, columns.amount).trim();
    if (dateText.isEmpty || name.isEmpty || amountText.isEmpty) return null;

    final accountName = _cell(row, columns.account).trim();
    final accountMask = _cell(row, columns.accountMask).trim();
    final status = _cell(row, columns.status).trim().toLowerCase();
    final noteText = _cell(row, columns.note).trim();
    final typeText = _cell(row, columns.type).trim();
    final excluded =
        _cell(row, columns.excluded).trim().toLowerCase() == 'true';
    final recurringText = _cell(row, columns.recurring).trim();

    return ParsedCopilotRow(
      dateText: dateText,
      name: name,
      amountText: amountText,
      accountName: accountName,
      accountMask: accountMask,
      status: status,
      categoryText: _cell(row, columns.category),
      note: noteText.isEmpty ? null : noteText,
      transactionType: typeText.isEmpty ? null : typeText,
      excluded: excluded,
      recurringSeries: recurringText.isEmpty ? null : recurringText,
      externalId: stableCopilotExternalId(
        dateText: dateText,
        name: name,
        amountText: amountText,
        accountName: accountName,
        accountMask: accountMask,
      ),
      postedAt: civilDate(dateText),
      // Copilot: expenses positive / income negative. Budgets: outflow negative.
      amountCents: -_parseAmountCents(amountText),
      pending: status == 'pending',
    );
  }

  static String _cell(List<dynamic> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index].toString();
  }

  static int _parseAmountCents(String raw) {
    final cleaned = raw.replaceAll(r'$', '').replaceAll(',', '').trim();
    if (cleaned.isEmpty) return 0;
    return cleaned.asCents;
  }
}

/// Stable across pending→posted / note edits. Name is lowercased so casing
/// differences do not create duplicate external ids.
String stableCopilotExternalId({
  required String dateText,
  required String name,
  required String amountText,
  required String accountName,
  required String accountMask,
}) {
  final material = [
    dateText,
    name.trim().toLowerCase(),
    amountText,
    accountName,
    accountMask,
  ].join('|');
  return 'copilot:${base64Url.encode(utf8.encode(material))}';
}

/// Copilot dates are calendar days — keep local Y/M/D.
DateTime civilDate(String dateText) {
  final parsed = DateTime.parse(dateText);
  return DateTime(parsed.year, parsed.month, parsed.day);
}
