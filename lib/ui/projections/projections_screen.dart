import 'package:ethan_sync/ethan_sync.dart';
import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/app_identity.dart';
import 'package:spend_trends/domain/projection/retirement_projection.dart';
import 'package:spend_trends/ui/projections/projection_assumptions_card.dart';
import 'package:spend_trends/ui/projections/projection_chart_card.dart';
import 'package:spend_trends/ui/projections/projection_headline_card.dart';
import 'package:spend_trends/ui/projections/projection_starting_point_card.dart';
import 'package:spend_trends/ui/projections/fire_outlook_card.dart';
import 'package:spend_trends/ui/projections/projections_providers.dart';
import 'package:spend_trends/ui/projections/roth_conversion_card.dart';

/// Retirement projection from live balances and last year's flows, with the
/// assumptions that drive it.
class const ProjectionsScreen() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RetirementProjection> projectionAsync = ref.watch(
      draftedRetirementProjectionProvider,
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const EAppHeader(
        eyebrow: AppIdentity.displayName,
        title: 'Projections',
        leading: ESyncPhaseIcon(),
        automaticallyImplyLeading: false,
        actions: [FireOutlookCard()],
      ),
      body: SafeArea(
        bottom: false,
        child: projectionAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => ELoadErrorView(
            screenName: 'Projections',
            error: error,
            stackTrace: stackTrace,
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
        _summariesBesideAssumptions(projection),
      ],
    );
  }

  /// Roth conversions over the starting point, beside the taller
  /// assumptions, when there is room; all three stacked otherwise.
  Widget _summariesBesideAssumptions(RetirementProjection projection) {
    return EBalancedRowsTileGrid(
      minTileWidth: 400,
      tiles: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: ELayout.spaceLg,
          children: [
            if (projection.currentAge != null)
              RothConversionCard(projection: projection),
            ProjectionStartingPointCard(projection: projection),
          ],
        ),
        ProjectionAssumptionsCard(projection: projection),
      ],
    );
  }
}
