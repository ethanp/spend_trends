import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/app_identity.dart';
import 'package:spend_trends/ui/projections/fire_outlook_card.dart';
import 'package:spend_trends/domain/projection/life_event.dart';
import 'package:spend_trends/ui/life_events/life_event_form_sheet.dart';
import 'package:spend_trends/ui/theme/life_event_lane_color.dart';
import 'package:spend_trends/ui/widgets/app_primary_button.dart';

import 'package:spend_trends/data/repositories/life_events_repository.dart';

const _logger = ELogger('LifeEventsScreen');

class const LifeEventsScreen() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lifeEventsAsync = ref.watch(lifeEventsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: 'Life Events',
        leading: const ESyncPhaseIcon(),
        automaticallyImplyLeading: false,
        actions: [
          const FireOutlookCard(),
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
          data: (lifeEvents) => _LifeEventsBody(lifeEvents: lifeEvents),
        ),
      ),
    );
  }
}

class const _LifeEventsBody({required final List<LifeEvent> lifeEvents})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: ETabBarOverlay.paddingOf(context),
      children: [
        if (lifeEvents.isEmpty)
          _noLifeEventsCard(context, ref)
        else
          for (final lifeEventLane in LifeEventLane.values)
            ..._laneSection(context, ref, lifeEventLane),
      ],
    );
  }

  Widget _noLifeEventsCard(BuildContext context, WidgetRef ref) {
    return ECard(
      kind: ESurfaceKind.row,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'No life events yet',
            style: EText.section.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: ELayout.spaceXs),
          Text(
            'Homes, jobs, and other dates show as lanes on Trends.',
            style: EText.caption,
          ),
          const SizedBox(height: ELayout.spaceMd),
          AppPrimaryButton(
            onPressed: () => LifeEventFormSheet.show(context, ref: ref),
            child: const Text('Add life event'),
          ),
        ],
      ),
    );
  }

  /// The lane's title in its Trends color, then its events newest first.
  List<Widget> _laneSection(
    BuildContext context,
    WidgetRef ref,
    LifeEventLane lifeEventLane,
  ) {
    final laneLifeEvents = lifeEvents.whereL(
      (lifeEvent) => lifeEvent.kind.lane == lifeEventLane,
    );
    if (laneLifeEvents.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(
          top: ELayout.spaceMd,
          bottom: ELayout.spaceSm,
        ),
        child: Text(
          lifeEventLane.title,
          style: EText.body.medium.copyWith(
            color: lifeEventLane.color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      for (var index = 0; index < laneLifeEvents.length; index++) ...[
        if (index > 0) const SizedBox(height: ELayout.spaceSm),
        _LifeEventListTile(
          lifeEvent: laneLifeEvents[index],
          onActivated: () => LifeEventFormSheet.show(
            context,
            ref: ref,
            lifeEvent: laneLifeEvents[index],
          ),
        ),
      ],
    ];
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
      child: ECard(
        kind: ESurfaceKind.row,
        padding: const EdgeInsets.all(ELayout.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lifeEvent.title,
              style: EText.section.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: ELayout.spaceXs),
            Text(
              lifeEvent.kind.lane.holdsOneKind
                  ? lifeEvent.dateCaption
                  : '${lifeEvent.kind.label} · ${lifeEvent.dateCaption}',
              style: EText.caption,
            ),
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
