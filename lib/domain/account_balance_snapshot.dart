/// A manual account's balance as recorded on [recordedOn].
class const AccountBalanceSnapshot({
  required final String id,
  required final String accountId,
  required final int balanceCents,
  required final DateTime recordedOn,
});
