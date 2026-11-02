class const MonthSummary({
  required final String yearMonth,
  required final int outflowCents,
  required final int inflowCents,
  required final List<AccountSpendRow> accountSpend,
  final DateTime? lastSyncedAt,
}) {
  /// Outflow is a positive spend total, so net is income minus spent.
  int get netCents => inflowCents - outflowCents;
}

class const AccountSpendRow({
  required final String accountId,
  required final String accountName,
  required final int spentCents,
});
