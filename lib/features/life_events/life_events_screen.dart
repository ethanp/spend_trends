import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spend_trends/app_identity.dart';
import 'package:spend_trends/domain/life_event.dart';
import 'package:spend_trends/domain/stay_chain.dart';
import 'package:spend_trends/features/life_chains/life_chain_screen.dart';
import 'package:spend_trends/features/life_events/life_event_form_sheet.dart';
import 'package:spend_trends/features/life_chains/life_chain_providers.dart';
import 'package:spend_trends/widgets/app_card.dart';
import 'package:spend_trends/widgets/app_primary_button.dart';
import 'life_events_providers.dart';

const _logger = ELogger('LifeEventsScreen');

class const LifeEventsScreen() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lifeEventsAsync = ref.watch(lifeEventsProvider);
    final housingAsync = ref.watch(housingChainProvider);
    final jobAsync = ref.watch(jobChainProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: 'Life Events',
        leading: const ESyncPhaseIcon(),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => LifeEventFormSheet.show(context, ref: ref),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: lifeEventsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) {
            _logger.log('LifeEventsProvider error: $error\n$stackTrace');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(ELayout.spaceLg),
                child: SelectableText(
                  '$error',
                  style: EText.body.medium.copyWith(color: EColors.danger),
                ),
              ),
            );
          },
          data: (lifeEvents) => _LifeEventsBody(
            lifeEvents: lifeEvents,
            housingChain: housingAsync.asData?.value,
            jobChain: jobAsync.asData?.value,
          ),
        ),
      ),
    );
  }
}

class const _LifeEventsBody({
  required final List<LifeEvent> lifeEvents,
  required final StayChain? housingChain,
  required final StayChain? jobChain,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(ELayout.spaceLg)
          .withOverlaidTabBar(context),
      children: [
        _LifeChainHeroCard(kind: LifeChainKind.housing, chain: housingChain),
        const SizedBox(height: ELayout.spaceSm),
        _LifeChainHeroCard(kind: LifeChainKind.job, chain: jobChain),
        const SizedBox(height: ELayout.spaceLg),
        Text(
          'Milestones',
          style: EText.body.medium.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: ELayout.spaceSm),
        if (lifeEvents.isEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'No milestones yet',
                  style: EText.section.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: ELayout.spaceXs),
                Text(
                  'One-off dates and ranges still show on Trends.',
                  style: EText.caption,
                ),
                const SizedBox(height: ELayout.spaceMd),
                AppPrimaryButton(
                  onPressed: () => LifeEventFormSheet.show(context, ref: ref),
                  child: const Text('Add life event'),
                ),
              ],
            ),
          )
        else
          for (var index = 0; index < lifeEvents.length; index++) ...[
            if (index > 0) const SizedBox(height: ELayout.spaceSm),
            _LifeEventListTile(
              lifeEvent: lifeEvents[index],
              onActivated: () => LifeEventFormSheet.show(
                context,
                ref: ref,
                lifeEvent: lifeEvents[index],
              ),
            ),
          ],
      ],
    );
  }
}

class const _LifeChainHeroCard({
  required final LifeChainKind kind,
  required final StayChain? chain,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final current = chain?.current;
    final accent = kind.trendBandColor;
    final caption = current == null
        ? kind.emptyHeroCaption
        : '${current.stay.label} · since '
              '${DateFormat.yMMMd().format(current.rangeStart)}';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => LifeChainScreen(kind: kind)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(ELayout.spaceMd),
        decoration: BoxDecoration(
          color: EColors.backgroundLift,
          borderRadius: ELayout.borderRadiusMd,
          border: Border.all(color: accent.withValues(alpha: 0.4)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.14), EColors.backgroundLift],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.22),
              ),
              child: Icon(kind.icon, color: accent, size: 22),
            ),
            const SizedBox(width: ELayout.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind.screenTitle,
                    style: EText.section.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: EText.caption.copyWith(color: EColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
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

class const _LifeEventListTile({
  required final LifeEvent lifeEvent,
  required final VoidCallback onActivated,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onActivated,
      child: AppCard(
        padding: const EdgeInsets.all(ELayout.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lifeEvent.title,
              style: EText.section.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: ELayout.spaceXs),
            Text(lifeEvent.dateCaption, style: EText.caption),
            if (lifeEvent.note != null) ...[
              const SizedBox(height: ELayout.spaceXs),
              Text(lifeEvent.note!, style: EText.caption),
            ],
          ],
        ),
      ),
    );
  }
}
