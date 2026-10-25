import 'package:ethan_utils/ethan_utils.dart';
import 'package:spend_trends/domain/account_kind.dart';
import 'package:spend_trends/domain/account_tax_treatment.dart';

class const Account({
  required final String id,
  required final String externalId,

  /// Official name from SimpleFIN / CSV import.
  required final String name,
  required final String currency,
  required final int balanceCents,
  final DateTime? balanceAsOf,
  final String? connId,
  final String? connName,
  final DateTime? lastSyncedAt,
  required final AccountStatus status,
  final String? statusMessage,

  /// Optional user-visible name; when set, [displayName] prefers it.
  final String? userLabel,

  /// Optional user-visible bank/institution name; when set,
  /// [institutionDisplayName] prefers it over [connName].
  final String? connUserLabel,

  /// Persisted account class (Checking, Investment, …); user-editable.
  final AccountKind kind = AccountKind.other,

  /// Live account this row is a prior version of (servicer handoff or
  /// Copilot history folded into SimpleFIN).
  final String? belongsToAccountId,

  /// Set on Banks; null means [AccountTaxTreatment.inferredFor] decides.
  final AccountTaxTreatment? chosenTaxTreatment,
}) {
  AccountTaxTreatment get taxTreatment =>
      chosenTaxTreatment ?? AccountTaxTreatment.inferredFor(this);

  /// Name shown throughout the app.
  String get displayName {
    final label = userLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    return name;
  }

  /// [displayName] prefixed with [institutionDisplayName] when the institution
  /// is meaningful (not the generic “Other” bucket).
  ///
  /// Use wherever the account appears without a separate institution header.
  String get displayNameWithInstitution {
    final account = displayName;
    final institution = institutionDisplayName;
    if (institution == 'Other') return account;
    if (account.toLowerCase().startsWith(institution.toLowerCase())) {
      return account;
    }
    return '$institution · $account';
  }

  /// Bank/institution name shown in Banks grouping headers.
  String get institutionDisplayName {
    if (isCopilot) return 'Copilot';
    final label = connUserLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    final official = connName?.trim();
    if (official != null && official.isNotEmpty) return official;
    return 'Other';
  }

  /// Stable key for grouping accounts under one bank (prefers [connId]).
  String get institutionGroupKey {
    if (isCopilot) return 'copilot';
    return Account.institutionGroupKeyFor(connId: connId, connName: connName);
  }

  /// Same grouping as [institutionGroupKey] for a SimpleFIN connection that
  /// is not a Copilot import.
  static String institutionGroupKeyFor({String? connId, String? connName}) {
    final id = connId?.trim();
    if (id != null && id.isNotEmpty) return 'id:$id';
    final official = connName?.trim();
    if (official != null && official.isNotEmpty) return 'name:$official';
    return 'other';
  }

  bool get isCopilot => externalId.startsWith('copilot:');

  /// Imported from an aggregator export (e.g. Empower) for its history only:
  /// a closed plan or one SimpleFIN cannot reach.
  bool get isHistoryImport => externalId.startsWith('history:');

  /// Valued by hand (an institution SimpleFIN cannot reach); its balance
  /// comes from recorded snapshots.
  bool get isManual => externalId.startsWith('manual:');

  /// Synced from SimpleFIN, so it has a live balance and can be pulled.
  /// Copilot and history imports carry transactions only.
  bool get isFromSimpleFin =>
      externalId.isNotEmpty && !isCopilot && !isHistoryImport && !isManual;

  bool get hasLiveBalance => isFromSimpleFin || isManual;

  /// A manual balance older than this needs looking up again; nothing
  /// refreshes it.
  static const manualBalanceFreshFor = Duration(days: 60);

  /// A manual account with no balance, or one older than
  /// [manualBalanceFreshFor] as of [now].
  bool isManualBalanceStale(DateTime now) =>
      isManual &&
      (balanceAsOf == null ||
          now.difference(balanceAsOf!) > manualBalanceFreshFor);

  /// Where the account's balance and transactions come from.
  String get sourceName {
    if (isCopilot) return 'copilot';
    if (isHistoryImport) return 'history';
    if (isManual) return 'manual';
    return 'simplefin';
  }

  String get balanceCaption => hasLiveBalance ? formatCents(balanceCents) : '—';

  bool get hasParent => belongsToAccountId != null;

  /// Live root balances only. Linked prior accounts and Copilot rows fold
  /// into a parent instead of adding a second balance.
  bool get countsTowardNetWorth => hasLiveBalance && !hasParent;

  /// Root accounts whose past balances belong in net worth history, including
  /// closed plans imported for their history (valued by imported snapshots).
  bool get countsTowardNetWorthHistory =>
      (hasLiveBalance || isHistoryImport) && !hasParent;

  /// Valued only by recorded snapshots: nothing pulls a balance or walks
  /// one back through transactions.
  bool get isValuedBySnapshots => isManual || isHistoryImport;

  bool get isInvestment => kind == AccountKind.investment;

  Account copyWith({
    String? id,
    String? externalId,
    String? name,
    String? currency,
    int? balanceCents,
    DateTime? balanceAsOf,
    String? connId,
    String? connName,
    DateTime? lastSyncedAt,
    AccountStatus? status,
    String? statusMessage,
    String? userLabel,
    bool clearUserLabel = false,
    String? connUserLabel,
    bool clearConnUserLabel = false,
    AccountKind? kind,
    String? belongsToAccountId,
    bool clearBelongsTo = false,
    AccountTaxTreatment? chosenTaxTreatment,
  }) {
    return Account(
      id: id ?? this.id,
      externalId: externalId ?? this.externalId,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      balanceCents: balanceCents ?? this.balanceCents,
      balanceAsOf: balanceAsOf ?? this.balanceAsOf,
      connId: connId ?? this.connId,
      connName: connName ?? this.connName,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      status: status ?? this.status,
      statusMessage: statusMessage ?? this.statusMessage,
      userLabel: clearUserLabel ? null : (userLabel ?? this.userLabel),
      connUserLabel: clearConnUserLabel
          ? null
          : (connUserLabel ?? this.connUserLabel),
      kind: kind ?? this.kind,
      belongsToAccountId: clearBelongsTo
          ? null
          : (belongsToAccountId ?? this.belongsToAccountId),
      chosenTaxTreatment: chosenTaxTreatment ?? this.chosenTaxTreatment,
    );
  }
}

enum AccountStatus() {
  ok,
  stale,
  needsRelink,
  error;

  static AccountStatus fromStorage(String value) {
    return AccountStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => AccountStatus.error,
    );
  }

  String get storageValue => name;
}
