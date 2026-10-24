import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/app_identity.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/features/projections/projection_assumptions_card.dart';
import 'package:spend_trends/features/projections/projection_chart_card.dart';
import 'package:spend_trends/features/projections/projection_headline_card.dart';
import 'package:spend_trends/features/projections/projection_starting_point_card.dart';
import 'package:spend_trends/features/projections/projections_providers.dart';

/// Retirement projection from live balances and last year's flows, with the
/// assumptions that drive it.
class const ProjectionsScreen() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RetirementProjection> projectionAsync = ref.watch(
      retirementProjectionProvider,
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: 'Projections',
        leading: ESyncPhaseIcon(),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        bottom: false,
        child: projectionAsync.when(
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
          data: (projection) => _projectionBody(context, projection),
        ),
      ),
    );
  }

  Widget _projectionBody(
    BuildContext context,
    RetirementProjection projection,
  ) {
    return ListView(
      padding: ETabBarOverlay.paddingOf(context),
      children: [
        ProjectionHeadlineCard(projection: projection),
        if (projection.currentAge != null) ...[
          const SizedBox(height: ELayout.spaceLg),
          ProjectionChartCard(projection: projection),
        ],
        const SizedBox(height: ELayout.spaceLg),
        ProjectionStartingPointCard(projection: projection),
        const SizedBox(height: ELayout.spaceLg),
        ProjectionAssumptionsCard(assumptions: projection.assumptions),
      ],
    );
  }
}
