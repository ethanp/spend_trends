/// An account's balance as recorded on [recordedOn]: typed in for a manual
/// account, saved by a SimpleFIN pull, or imported from Empower.
class const AccountBalanceSnapshot({
  required final String id,
  required final String accountId,
  required final int balanceCents,
  required final DateTime recordedOn,
});
