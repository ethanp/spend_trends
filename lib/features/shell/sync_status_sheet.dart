import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/account.dart';
import 'package:spend_trends/features/banks/bank_pull_history_sheet.dart';
import 'package:spend_trends/features/banks/connection_status.dart';
import 'package:spend_trends/services/sqlite/simplefin_pull_history.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';

class const SyncStatusSheet() extends ConsumerWidget {
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SyncStatusSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionAsync = ref.watch(connectionStatusProvider);

    return AppSheetPanel(
      heightFraction: 0.55,
      padForKeyboard: false,
      child: connectionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(ELayout.spaceLg),
          child: Text(
            '$error',
            style: EText.body.medium.copyWith(color: EColors.danger),
          ),
        ),
        data: (status) => _SyncStatusBody(status: status),
      ),
    );
  }
}

class const _SyncStatusBody({required final ConnectionStatus status})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestFinished = status.latestFinishedPull;
    final issueByAccountId = <String, SimpleFinPullAccountRecord>{};
    if (latestFinished != null) {
      for (final account in latestFinished.accounts) {
        if (!account.status.isIssue) continue;
        final accountId = account.accountId;
        if (accountId == null) continue;
        issueByAccountId[accountId] = account;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(ELayout.spaceLg),
      children: [
        Text('Sync status', style: EText.section),
        const SizedBox(height: ELayout.spaceLg),
        _deviceSyncSection(ref),
        const SizedBox(height: ELayout.spaceLg),
        _bankSyncSection(context),
        if (status.errors.isNotEmpty) ...[
          const SizedBox(height: ELayout.spaceLg),
          _bridgeErrorsSection(),
        ],
        const SizedBox(height: ELayout.spaceLg),
        Text(
          'Accounts',
          style: EText.section.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceSm),
        if (!status.isConnected || status.accounts.isEmpty)
          Text(
            status.isConnected
                ? 'No accounts yet.'
                : 'Connect a bank on the Banks tab to sync accounts.',
            style: EText.body.medium,
          )
        else
          ...status.accounts.map(
            (account) => _AccountSyncRow(
              account: account,
              lastPullIssue: issueByAccountId[account.id],
            ),
          ),
      ],
    );
  }

  Widget _deviceSyncSection(WidgetRef ref) {
    if (!DotEnvSyncBootstrap.isConfigured()) {
      return _statusLine(label: 'Device sync', value: 'Not configured');
    }
    final offline = ref.watch(isOfflineProvider);
    final phase = ref.watch(syncPhaseProvider);
    return _statusLine(
      label: 'Device sync',
      value: offline ? 'Offline' : _phaseLabel(phase),
    );
  }

  Widget _bankSyncSection(BuildContext context) {
    if (!status.isConnected) {
      return _statusLine(label: 'Bank pull', value: 'Not connected');
    }

    final lastSyncedAt = status.lastSyncedAt;
    final primary = lastSyncedAt == null
        ? 'Never'
        : lastSyncedAt.relativeTimeAgo(includeClock: true);
    final secondary = _bankPullSecondaryLine();

    return InkWell(
      onTap: () => BankPullHistorySheet.show(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bank pull', style: EText.body.medium),
                Text(
                  primary,
                  style: EText.body.medium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (secondary != null)
                  Text(
                    secondary.text,
                    style: secondary.isError
                        ? EText.caption.copyWith(color: EColors.danger)
                        : secondary.isWarning
                        ? EText.caption.copyWith(color: EColors.warning)
                        : EText.caption,
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 16, color: EColors.textMuted),
        ],
      ),
    );
  }

  _SecondaryLine? _bankPullSecondaryLine() {
    final running = status.latestRunningPull;
    if (running != null) {
      return const _SecondaryLine('Pulling…');
    }
    final finished = status.latestFinishedPull;
    if (finished == null) return null;

    if (finished.status == SimpleFinPullStatus.failed) {
      final when = finished.finishedAt ?? finished.startedAt;
      return _SecondaryLine(
        'Last pull failed · ${when.relativeTimeAgo()}',
        isError: true,
      );
    }

    if (finished.isPartialSuccess) {
      final count = finished.issueAccountCount;
      return _SecondaryLine(
        '$count ${count == 1 ? 'account' : 'accounts'} had issues',
        isWarning: true,
      );
    }

    final txCount = finished.transactionCount ?? 0;
    return _SecondaryLine(
      'Last pull OK · ${finished.kind.displayLabel} · $txCount txs',
    );
  }

  Widget _bridgeErrorsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bridge warnings',
          style: EText.section.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceSm),
        for (final error in status.errors)
          Padding(
            padding: const EdgeInsets.only(bottom: ELayout.spaceXs),
            child: Text(
              error.message,
              style: EText.caption.copyWith(color: EColors.danger),
            ),
          ),
      ],
    );
  }

  Widget _statusLine({required String label, required String value}) {
    return Row(
      children: [
        Expanded(child: Text(label, style: EText.body.medium)),
        Text(
          value,
          style: EText.body.medium.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  String _phaseLabel(SyncPhase phase) {
    return switch (phase) {
      SyncPhase.connecting => 'Connecting',
      SyncPhase.downloading => 'Downloading',
      SyncPhase.uploading => 'Uploading',
      SyncPhase.synced => 'Synced',
      SyncPhase.offline => 'Offline',
      SyncPhase.error => 'Error',
    };
  }
}

class const _SecondaryLine(
  final String text, {
  final bool isError = false,
  final bool isWarning = false,
});

class const _AccountSyncRow({
  required final Account account,
  final SimpleFinPullAccountRecord? lastPullIssue,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final needsRelink = account.status == AccountStatus.needsRelink;
    final lastSyncedAt = account.lastSyncedAt;
    final issue = lastPullIssue;

    return Padding(
      padding: const EdgeInsets.only(bottom: ELayout.spaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.displayNameWithInstitution,
                  style: EText.section.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  needsRelink ? 'Needs re-link' : account.status.name,
                  style: needsRelink
                      ? EText.caption.copyWith(color: EColors.warning)
                      : EText.caption,
                ),
                if (issue != null)
                  Text(
                    'Last pull: ${_issueCaption(issue)}',
                    style:
                        issue.status == SimpleFinPullAccountStatus.needsRelink
                        ? EText.caption.copyWith(color: EColors.warning)
                        : EText.caption.copyWith(color: EColors.danger),
                  ),
              ],
            ),
          ),
          Text(
            lastSyncedAt == null
                ? 'Never'
                : lastSyncedAt.relativeTimeAgo(includeClock: true),
            style: EText.caption,
          ),
        ],
      ),
    );
  }

  static String _issueCaption(SimpleFinPullAccountRecord issue) {
    if (issue.status == SimpleFinPullAccountStatus.needsRelink) {
      return 'needs re-link';
    }
    final message = issue.errorMessage?.trim() ?? '';
    if (message.isNotEmpty) return message;
    return issue.status.displayLabel;
  }
}
