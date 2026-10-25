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
      draftedRetirementProjectionProvider,
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
        _assumptionsBesideStartingPoint(projection),
      ],
    );
  }

  /// Two columns when there is room; stacked otherwise.
  Widget _assumptionsBesideStartingPoint(RetirementProjection projection) {
    final assumptions = ProjectionAssumptionsCard(projection: projection);
    final startingPoint = ProjectionStartingPointCard(projection: projection);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _twoColumnMinWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              assumptions,
              const SizedBox(height: ELayout.spaceLg),
              startingPoint,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: assumptions),
            const SizedBox(width: ELayout.spaceLg),
            Expanded(child: startingPoint),
          ],
        );
      },
    );
  }

  static const _twoColumnMinWidth = 1000.0;
}
