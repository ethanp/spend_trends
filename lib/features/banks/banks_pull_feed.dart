import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/domain/transaction.dart';
import 'package:spend_trends/features/banks/banks_pull_live_session.dart';
import 'package:spend_trends/features/banks/banks_pull_transaction_list.dart';
import 'package:spend_trends/features/banks/pull_import_window.dart';
import 'package:spend_trends/services/sqlite/simplefin_pull_history.dart';
import 'package:spend_trends/theme/finance_colors.dart';

import 'banks_providers.dart';

/// In-screen pull history on Banks: date navigation and transaction review.
class const BanksPullFeed({
  final String? selectedTransactionId,
  final void Function(BankTransaction transaction)? onPullTransactionSelected,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<BanksPullFeed> createState() => _BanksPullFeedState();
}

class _BanksPullFeedState() extends ConsumerState<BanksPullFeed> {
  static final _dayFormat = DateFormat('MMMM d');
  static final _yearFormat = DateFormat('yyyy');
  static final _timeFormat = DateFormat('h:mm a');

  int _selectedPullIndex = 0;

  @override
  Widget build(BuildContext context) {
    ref.listen<BanksPullLiveSessionState?>(banksPullLiveSessionProvider, (
      previous,
      next,
    ) {
      if (previous == null && next != null && _selectedPullIndex != 0) {
        setState(() => _selectedPullIndex = 0);
      }
    });

    final pullsAsync = ref.watch(simpleFinPullHistoryListProvider);
    final BanksPullLiveSessionState? liveSession = ref.watch(
      banksPullLiveSessionProvider,
    );

    return pullsAsync.when(
      loading: () => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => SelectableText(
        '$error',
        style: EText.body.medium.copyWith(color: EColors.danger),
      ),
      data: (pulls) {
        if (pulls.isEmpty && liveSession == null) {
          return Text(
            'No bank pulls yet. Pull bank transactions to review them here.',
            style: EText.caption,
          );
        }

        final viewingLive = liveSession != null && _selectedPullIndex == 0;
        final selectedPull = viewingLive
            ? null
            : _historicalPullAt(
                selectedIndex: _selectedPullIndex,
                pulls: pulls,
                hasLiveSession: liveSession != null,
              );

        if (!(viewingLive || selectedPull != null)) {
          return Text('No pull at this position.', style: EText.caption);
        }

        final PullImportWindow importWindow = viewingLive
            ? PullImportWindow(
                startedAt: liveSession.startedAt.toUtc(),
                finishedAt: liveSession.finished
                    ? liveSession.finishedAt
                    : null,
              )
            : PullImportWindow(
                startedAt: selectedPull!.startedAt,
                finishedAt: selectedPull.finishedAt,
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dateNavigator(
              pulls: pulls,
              liveSession: liveSession,
              viewingLive: viewingLive,
              selectedPull: selectedPull,
            ),
            const SizedBox(height: ELayout.spaceMd),
            if (viewingLive) _liveStatus(liveSession),
            if (!viewingLive && selectedPull != null)
              _historicalStatus(selectedPull),
            const SizedBox(height: ELayout.spaceMd),
            _pullTransactions(importWindow),
          ],
        );
      },
    );
  }

  Widget _pullTransactions(PullImportWindow importWindow) {
    final transactionsAsync = ref.watch(
      pullImportedTransactionsProvider(importWindow),
    );
    return transactionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => SelectableText(
        '$error',
        style: EText.caption.copyWith(color: EColors.danger),
      ),
      data: (transactions) => BanksPullTransactionList(
        transactions: transactions,
        selectedTransactionId: widget.selectedTransactionId,
        onTransactionSelected: widget.onPullTransactionSelected ?? (_) {},
      ),
    );
  }

  Widget _dateNavigator({
    required List<SimpleFinPullRecord> pulls,
    required BanksPullLiveSessionState? liveSession,
    required bool viewingLive,
    required SimpleFinPullRecord? selectedPull,
  }) {
    final DateTime anchorDate = viewingLive
        ? liveSession!.startedAt
        : selectedPull!.startedAt;
    final localDate = anchorDate.toLocal();
    final canGoNewer = _selectedPullIndex > 0;
    final canGoOlder = liveSession != null
        ? _selectedPullIndex < pulls.length
        : _selectedPullIndex < pulls.length - 1;

    return ESurface(
      kind: ESurfaceKind.tinted,
      accent: FinanceColors.accentPrimary,
      padding: const EdgeInsets.symmetric(
        horizontal: ELayout.spaceSm,
        vertical: ELayout.spaceMd,
      ),
      borderRadius: ELayout.borderRadiusLg,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _navButton(
                icon: Icons.chevron_left,
                tooltip: 'Older pull',
                enabled: canGoOlder,
                onActivated: () => setState(() => _selectedPullIndex++),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      _dayFormat.format(localDate),
                      style: EText.title.copyWith(
                        fontSize: ELayout.typeSize(34),
                        fontWeight: FontWeight.w300,
                        height: 1.05,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      _yearFormat.format(localDate),
                      style: EText.caption.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              _navButton(
                icon: Icons.chevron_right,
                tooltip: 'Newer pull',
                enabled: canGoNewer,
                onActivated: () => setState(() => _selectedPullIndex--),
              ),
            ],
          ),
          const SizedBox(height: ELayout.spaceSm),
          Text(
            _subtitle(
              viewingLive: viewingLive,
              liveSession: liveSession,
              selectedPull: selectedPull,
              localDate: localDate,
            ),
            style: EText.caption,
            textAlign: TextAlign.center,
          ),
          if (pulls.isNotEmpty || liveSession != null) ...[
            const SizedBox(height: ELayout.spaceXs),
            Text(
              _positionLabel(
                pulls: pulls,
                liveSession: liveSession,
                selectedIndex: _selectedPullIndex,
              ),
              style: EText.caption.copyWith(color: EColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _navButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onActivated,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onActivated : null,
      icon: Icon(
        icon,
        color: enabled ? EColors.textPrimary : EColors.textMuted,
      ),
    );
  }

  Widget _liveStatus(BanksPullLiveSessionState session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!session.finished)
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: ELayout.spaceSm),
              Expanded(child: Text(session.statusLine, style: EText.caption)),
              Text(
                session.displayedElapsed.formattedElapsed,
                style: EText.caption.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: EColors.textMuted,
                ),
              ),
            ],
          )
        else
          Text(session.statusLine, style: EText.caption),
        if (session.queryWindowLine != null) ...[
          const SizedBox(height: ELayout.spaceXs),
          Text(
            session.queryWindowLine!,
            style: EText.caption.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
        if (session.errorMessage != null) ...[
          const SizedBox(height: ELayout.spaceSm),
          Text(
            session.errorMessage!,
            style: EText.caption.copyWith(color: EColors.danger),
          ),
        ],
      ],
    );
  }

  Widget _historicalStatus(SimpleFinPullRecord pull) {
    final accountCount = pull.accountCount ?? pull.accounts.length;
    final transactionCount = pull.transactionCount ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$accountCount ${accountCount == 1 ? 'account' : 'accounts'} · '
          '$transactionCount ${transactionCount == 1 ? 'transaction' : 'transactions'}',
          style: EText.body.medium.copyWith(fontWeight: FontWeight.w600),
        ),
        if (pull.errors.isNotEmpty) ...[
          const SizedBox(height: ELayout.spaceSm),
          for (final error in pull.errors)
            Padding(
              padding: const EdgeInsets.only(bottom: ELayout.spaceXs),
              child: SelectableText(
                error.message,
                style: EText.caption.copyWith(color: EColors.danger),
              ),
            ),
        ],
        if (pull.hasAccountIssues) ...[
          const SizedBox(height: ELayout.spaceSm),
          for (final account in pull.accounts)
            if (account.status.isIssue)
              Padding(
                padding: const EdgeInsets.only(bottom: ELayout.spaceXs),
                child: Text(
                  '${account.accountLabel}: '
                  '${account.errorMessage ?? account.status.displayLabel}',
                  style: EText.caption.copyWith(color: EColors.warning),
                ),
              ),
        ],
      ],
    );
  }

  String _subtitle({
    required bool viewingLive,
    required BanksPullLiveSessionState? liveSession,
    required SimpleFinPullRecord? selectedPull,
    required DateTime localDate,
  }) {
    final timeLabel = _timeFormat.format(localDate);
    if (viewingLive) {
      final session = liveSession!;
      if (!session.finished) return '$timeLabel · ${session.statusLine}';
      final accounts = session.overallAccounts ?? session.accounts.length;
      final transactions =
          session.overallTransactions ??
          session.accounts.fold<int>(
            0,
            (sum, account) => sum + account.transactionCount,
          );
      return '$timeLabel · $accounts '
          '${accounts == 1 ? 'account' : 'accounts'} · $transactions '
          '${transactions == 1 ? 'transaction' : 'transactions'}';
    }

    final pull = selectedPull!;
    final kindLabel = pull.kind.displayLabel;
    final statusLabel = switch (pull.status) {
      SimpleFinPullStatus.running => 'In progress',
      SimpleFinPullStatus.failed => 'Failed',
      SimpleFinPullStatus.success when pull.isPartialSuccess =>
        'Partial success',
      SimpleFinPullStatus.success => 'Success',
    };
    final duration = pull.duration;
    final durationLabel = duration == null
        ? timeLabel
        : '$timeLabel · ${duration.formattedSeconds}';
    return '$durationLabel · $kindLabel · $statusLabel';
  }

  String _positionLabel({
    required List<SimpleFinPullRecord> pulls,
    required BanksPullLiveSessionState? liveSession,
    required int selectedIndex,
  }) {
    final pullCount = pulls.length;
    if (pullCount <= 1 && liveSession == null) return 'Latest pull';
    final position = selectedIndex + 1;
    final total = liveSession != null ? pullCount + 1 : pullCount;
    return 'Pull $position of $total';
  }

  SimpleFinPullRecord? _historicalPullAt({
    required int selectedIndex,
    required List<SimpleFinPullRecord> pulls,
    required bool hasLiveSession,
  }) {
    final pullIndex = hasLiveSession ? selectedIndex - 1 : selectedIndex;
    if (pullIndex < 0 || pullIndex >= pulls.length) return null;
    return pulls[pullIndex];
  }
}
