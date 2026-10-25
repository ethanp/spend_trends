/// One day of net worth imported from an aggregator (Empower), covering the
/// years before this app recorded account balances itself.
class const ImportedNetWorthDay({
  required final DateTime recordedOn,
  required final int netWorthCents,
});
