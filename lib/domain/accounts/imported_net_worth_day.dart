import 'package:ethan_utils/ethan_utils.dart';

/// One day of net worth imported from an aggregator (Empower), covering the
/// years before this app recorded account balances itself.
class const ImportedNetWorthDay({
  required final CalendarDay day,
  required final int netWorthCents,
});
