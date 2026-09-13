import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/services/sqlite/simplefin_pull_history.dart';
import 'package:spend_trends/widgets/app_sheet_panel.dart';

import 'banks_providers.dart';

/// Browse recent SimpleFIN pulls and per-account outage outcomes.
class const BankPullHistorySheet() extends ConsumerStatefulWidget {
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BankPullHistorySheet(),
    );
  }

  @override
  ConsumerState<BankPullHistorySheet> createState() =>
      _BankPullHistorySheetState();
}

class _BankPullHistorySheetState() extends ConsumerState<BankPullHistorySheet> {
  String? _expandedPullId;

  @override
  Widget build(BuildContext context) {
    final pullsAsync = ref.watch(simpleFinPullHistoryListProvider);

    return AppSheetPanel(
      heightFraction: 0.72,
      padForKeyboard: false,
      child: pullsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(ELayout.spaceLg),
          child: Text(
            '$error',
            style: EText.body.medium.copyWith(color: EColors.danger),
          ),
        ),
        data: (pulls) => _body(pulls: pulls),
      ),
    );
  }

  Widget _body({required List<SimpleFinPullRecord> pulls}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ELayout.spaceLg,
            ELayout.spaceLg,
            ELayout.spaceLg,
            ELayout.spaceSm,
          ),
          child: Text('Bank pulls', style: EText.section),
        ),
        Expanded(
          child: pulls.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(ELayout.spaceLg),
                  child: Text(
                    'No bank pulls yet. Pull from the Banks tab.',
                    style: EText.body.medium,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ELayout.spaceLg,
                  ),
                  itemCount: pulls.length,
                  itemBuilder: (context, index) {
                    final pull = pulls[index];
                    return _PullHistoryRow(
                      pull: pull,
                      expanded: _expandedPullId == pull.id,
                      onActivated: () {
                        setState(() {
                          _expandedPullId = _expandedPullId == pull.id
                              ? null
                              : pull.id;
                        });
                      },
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(ELayout.spaceLg),
          child: Text(
            'Start a pull from the Banks tab to see live progress there.',
            style: EText.caption,
          ),
        ),
      ],
    );
  }
}

class const _PullHistoryRow({
  required final SimpleFinPullRecord pull,
  required final bool expanded,
  required final VoidCallback onActivated,
}) extends StatelessWidget {
  static final _whenFormat = DateFormat('MMM d · h:mm a');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ELayout.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onActivated,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(_leadingIcon, size: 18, color: _leadingColor),
                ),
                const SizedBox(width: ELayout.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pull.kind.displayLabel,
                        style: EText.section.copyWith(
                          fontSize: ELayout.typeSize(17),
                        ),
                      ),
                      Text(_subtitle, style: EText.caption),
                    ],
                  ),
                ),
                if (pull.transactionCount != null)
                  Text('${pull.transactionCount} txs', style: EText.caption),
                const SizedBox(width: ELayout.spaceXs),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 14,
                  color: EColors.textMuted,
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: ELayout.spaceSm),
            _PullDetail(pull: pull),
          ],
        ],
      ),
    );
  }

  IconData get _leadingIcon {
    if (pull.status == SimpleFinPullStatus.running) {
      return Icons.sync;
    }
    if (pull.status == SimpleFinPullStatus.failed) {
      return Icons.cancel;
    }
    if (pull.isPartialSuccess) {
      return Icons.warning;
    }
    return Icons.check_circle;
  }

  Color get _leadingColor {
    if (pull.status == SimpleFinPullStatus.failed) return EColors.danger;
    if (pull.isPartialSuccess) return EColors.warning;
    if (pull.status == SimpleFinPullStatus.success) return EColors.success;
    return EColors.textMuted;
  }

  String get _subtitle {
    final when = _whenFormat.format(pull.startedAt.toLocal());
    final duration = pull.duration;
    if (duration == null) return when;
    return '$when · ${_formatDuration(duration)}';
  }

  static String _formatDuration(Duration duration) {
    if (duration.inMinutes >= 1) {
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      if (seconds == 0) return '${minutes}m';
      return '${minutes}m ${seconds}s';
    }
    return '${duration.inSeconds}s';
  }
}

class const _PullDetail({required final SimpleFinPullRecord pull})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final accountCount = pull.accountCount ?? pull.accounts.length;
    final transactionCount = pull.transactionCount ?? 0;
    final sortedAccounts = [...pull.accounts]
      ..sort((left, right) {
        final severity = right.status.severityRank.compareTo(
          left.status.severityRank,
        );
        if (severity != 0) return severity;
        return left.accountLabel.compareTo(right.accountLabel);
      });

    return Padding(
      padding: const EdgeInsets.only(left: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$accountCount ${accountCount == 1 ? 'account' : 'accounts'} · '
            '$transactionCount ${transactionCount == 1 ? 'transaction' : 'transactions'}',
            style: EText.caption,
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
          if (sortedAccounts.isNotEmpty) ...[
            const SizedBox(height: ELayout.spaceSm),
            Text(
              'Accounts in this pull',
              style: EText.caption.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: ELayout.spaceXs),
            ..._groupedAccountRows(sortedAccounts),
          ],
        ],
      ),
    );
  }

  List<Widget> _groupedAccountRows(List<SimpleFinPullAccountRecord> accounts) {
    final groups = <String, List<SimpleFinPullAccountRecord>>{};
    for (final account in accounts) {
      final key = account.connId?.trim();
      final groupKey = (key == null || key.isEmpty)
          ? account.accountLabel
          : key;
      groups.putIfAbsent(groupKey, () => []).add(account);
    }

    final widgets = <Widget>[];
    for (final groupAccounts in groups.values) {
      final showInstitutionHeader =
          groupAccounts.length > 1 && groupAccounts.first.connId != null;
      if (showInstitutionHeader) {
        final sample = groupAccounts.first.accountLabel;
        final institution = sample.contains(' · ')
            ? sample.split(' · ').first
            : sample;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: ELayout.spaceXs),
            child: Text(institution, style: EText.caption),
          ),
        );
      }
      for (final account in groupAccounts) {
        widgets.add(_accountRow(account));
      }
    }
    return widgets;
  }

  Widget _accountRow(SimpleFinPullAccountRecord account) {
    final statusStyle = account.status.isIssue
        ? (account.status == SimpleFinPullAccountStatus.needsRelink
              ? EText.caption.copyWith(color: EColors.warning)
              : EText.caption.copyWith(color: EColors.danger))
        : EText.caption;
    final detail = account.status.isIssue
        ? (account.errorMessage?.trim().isNotEmpty == true
              ? account.errorMessage!
              : account.status.displayLabel)
        : '${account.transactionCount} txs';

    return Padding(
      padding: const EdgeInsets.only(top: ELayout.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(account.accountLabel, style: EText.caption)),
          const SizedBox(width: ELayout.spaceSm),
          Flexible(
            child: Text(detail, style: statusStyle, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
