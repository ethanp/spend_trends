import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/services/simplefin/simplefin_pull_progress.dart';
import 'package:spend_trends/theme/finance_colors.dart';

/// One progress bar per bank while a pull is downloading.
class const BanksPullBankBars({
  required final List<SimpleFinBankLoad> banks,
  final int? windowIndex,
  final int? windowCount,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (banks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < banks.length; index++) ...[
          if (index > 0) const SizedBox(height: ELayout.spaceMd),
          _bankBar(banks[index]),
        ],
      ],
    );
  }

  Widget _bankBar(SimpleFinBankLoad bank) {
    final value = _barValue(bank);
    final failed = bank.phase == SimpleFinBankLoadPhase.failed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                bank.name,
                style: EText.body.medium.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: ELayout.spaceSm),
            Text(
              _progressLabel(bank),
              style: EText.caption.copyWith(
                color: failed ? EColors.danger : EColors.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: ELayout.spaceXs),
        LinearProgressIndicator(
          value: value,
          minHeight: 4,
          backgroundColor: EColors.border,
          color: failed ? EColors.danger : FinanceColors.accentPrimary,
        ),
        if (failed && bank.errorMessage != null) ...[
          const SizedBox(height: ELayout.spaceXs),
          Text(
            bank.errorMessage!,
            style: EText.caption.copyWith(color: EColors.danger),
          ),
        ],
      ],
    );
  }

  double? _barValue(SimpleFinBankLoad bank) {
    final inner = bank.receivedFraction;
    final count = windowCount;
    final index = windowIndex;
    if (count == null || count <= 1 || index == null) return inner;
    final completedWindows = index - 1;
    if (bank.phase == SimpleFinBankLoadPhase.receiving && inner == null) {
      return completedWindows / count;
    }
    return (completedWindows + (inner ?? 0)) / count;
  }

  String _progressLabel(SimpleFinBankLoad bank) {
    switch (bank.phase) {
      case SimpleFinBankLoadPhase.waiting:
        return 'Waiting';
      case SimpleFinBankLoadPhase.receiving:
        final fraction = bank.receivedFraction;
        if (fraction != null) return '${(fraction * 100).round()}%';
        return _byteLabel(bank.bytesReceived);
      case SimpleFinBankLoadPhase.saving:
        return 'Saving';
      case SimpleFinBankLoadPhase.done:
        return 'Done';
      case SimpleFinBankLoadPhase.failed:
        return 'Failed';
    }
  }

  String _byteLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
