import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/app_identity.dart';
import 'package:spend_trends/domain/stay_chain.dart';
import 'package:spend_trends/features/life_chains/chain_stay_form_sheet.dart';
import 'package:spend_trends/providers/spend_trends_providers.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';

class const LifeChainScreen({required final LifeChainKind kind})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chainAsync = switch (kind) {
      LifeChainKind.housing => ref.watch(housingChainProvider),
      LifeChainKind.job => ref.watch(jobChainProvider),
    };

    return EScaffoldShell(
      appBar: EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: kind.screenTitle,
      ),
      body: chainAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(ELayout.spaceLg),
            child: Text(
              '$error',
              style: EText.body.medium.copyWith(color: EColors.danger),
            ),
          ),
        ),
        data: (chain) => _ChainBody(kind: kind, chain: chain),
      ),
    );
  }
}

class const _ChainBody({
  required final LifeChainKind kind,
  required final StayChain chain,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ELayout.spaceLg,
        ELayout.spaceMd,
        ELayout.spaceLg,
        ELayout.spaceXl,
      ).withOverlaidTabBar(context),
      children: [
        Text(
          kind == LifeChainKind.housing
              ? 'Where you’ve lived — a path of places over time.'
              : 'Where you’ve worked — a path of roles over time.',
          style: EText.body.medium.copyWith(color: EColors.textMuted),
        ),
        const SizedBox(height: ELayout.spaceLg),
        if (chain.isEmpty)
          _EmptyChain(kind: kind)
        else
          _ChainPath(kind: kind, chain: chain),
        const SizedBox(height: ELayout.spaceXl),
        AppPrimaryButton(
          onPressed: () {
            final oldestStartedOn = chain.oldest?.stay.startedOn.startOfDay;
            ChainStayFormSheet.show(
              context,
              ref: ref,
              kind: kind,
              initialStartedOn: oldestStartedOn?.subtract(
                const Duration(days: 1),
              ),
            );
          },
          child: Text(kind.addCta),
        ),
      ],
    );
  }
}

class const _EmptyChain({required final LifeChainKind kind})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 32,
        horizontal: ELayout.spaceLg,
      ),
      decoration: BoxDecoration(
        color: EColors.backgroundLift,
        borderRadius: ELayout.borderRadiusMd,
        border: Border.all(color: EColors.border),
      ),
      child: Column(
        children: [
          Icon(kind.icon, size: 36, color: kind.trendBandColor),
          const SizedBox(height: ELayout.spaceMd),
          Text(kind.emptyHeroCaption, style: EText.section),
          const SizedBox(height: ELayout.spaceSm),
          Text(
            'Add the first link to start the chain.',
            style: EText.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class const _ChainPath({
  required final LifeChainKind kind,
  required final StayChain chain,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segmentsNewestFirst = chain.segments.reversed.toList();

    return Column(
      children: [
        for (var index = 0; index < segmentsNewestFirst.length; index++) ...[
          if (index > 0) _PathConnector(color: kind.trendBandColor),
          _StayNode(
            kind: kind,
            segment: segmentsNewestFirst[index],
            onActivated: () => ChainStayFormSheet.show(
              context,
              ref: ref,
              kind: kind,
              stay: segmentsNewestFirst[index].stay,
            ),
          ),
        ],
      ],
    );
  }
}

class const _PathConnector({required final Color color})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Center(
        child: Container(
          width: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.55),
                color.withValues(alpha: 0.2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class const _StayNode({
  required final LifeChainKind kind,
  required final ChainStaySegment segment,
  required final VoidCallback onActivated,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final accent = kind.trendBandColor;
    final isCurrent = segment.isCurrent;

    return GestureDetector(
      onTap: onActivated,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(ELayout.spaceMd),
        decoration: BoxDecoration(
          color: isCurrent
              ? accent.withValues(alpha: 0.12)
              : EColors.backgroundLift,
          borderRadius: ELayout.borderRadiusMd,
          border: Border.all(
            color: isCurrent ? accent.withValues(alpha: 0.55) : EColors.border,
            width: isCurrent ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: isCurrent ? 44 : 36,
              height: isCurrent ? 44 : 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCurrent
                    ? accent.withValues(alpha: 0.28)
                    : EColors.surfaceRaised,
                border: Border.all(
                  color: isCurrent ? accent : EColors.borderStrong,
                ),
              ),
              child: Icon(
                kind.icon,
                size: isCurrent ? 22 : 18,
                color: isCurrent ? accent : EColors.textMuted,
              ),
            ),
            const SizedBox(width: ELayout.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isCurrent) ...[
                    Text(
                      kind.currentCaption,
                      style: EText.caption.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    segment.stay.label,
                    style: EText.section.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isCurrent
                          ? EColors.textPrimary
                          : EColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: ELayout.spaceXs),
                  Text(
                    segment.dateCaption,
                    style: EText.caption.copyWith(
                      color: isCurrent
                          ? EColors.textSecondary
                          : EColors.textMuted,
                    ),
                  ),
                  if (segment.stay.note != null) ...[
                    const SizedBox(height: ELayout.spaceXs),
                    Text(segment.stay.note!, style: EText.caption),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: EColors.textMuted),
          ],
        ),
      ),
    );
  }
}
