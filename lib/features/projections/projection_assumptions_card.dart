import 'package:ethan_ui/ethan_ui.dart';
import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spend_trends/domain/projection/projection_assumptions.dart';
import 'package:spend_trends/features/projections/projections_providers.dart';
import 'package:spend_trends/widgets/app_card.dart';

/// How an assumption's text becomes its JSON value.
enum _AssumptionInputKind() {
  wholeNumber,
  decimal,

  /// Blank clears it (overrides).
  optionalWholeNumber,

  /// `YYYY-MM-DD`; blank clears it.
  optionalDay,

  /// Comma-separated years.
  yearList,
}

class const _AssumptionInput({
  required final String key,
  required final String label,
  required final String text,
  required final _AssumptionInputKind kind,
  final String hint = '',
});

/// Editable projection assumptions; each field saves when you leave it.
class const ProjectionAssumptionsCard({
  required final ProjectionAssumptions assumptions,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Assumptions', style: EText.section),
          const SizedBox(height: ELayout.spaceXs),
          Text(
            'Today’s dollars. Overrides replace the live take-home and '
            'non-housing spending; leave blank to use live data.',
            style: EText.caption,
          ),
          const SizedBox(height: ELayout.spaceSm),
          for (final input in _inputs())
            _AssumptionField(key: ValueKey(input.key), input: input),
        ],
      ),
    );
  }

  List<_AssumptionInput> _inputs() => [
    _AssumptionInput(
      key: 'birthDate',
      label: 'Birth date',
      text: assumptions.birthDate?.dayKey ?? '',
      kind: _AssumptionInputKind.optionalDay,
      hint: 'YYYY-MM-DD',
    ),
    _AssumptionInput(
      key: 'retirementAge',
      label: 'Planned retirement age',
      text: '${assumptions.retirementAge}',
      kind: _AssumptionInputKind.wholeNumber,
    ),
    _AssumptionInput(
      key: 'endAge',
      label: 'Plan through age',
      text: '${assumptions.endAge}',
      kind: _AssumptionInputKind.wholeNumber,
    ),
    _AssumptionInput(
      key: 'realReturnPercent',
      label: 'Real return %',
      text: '${assumptions.realReturnPercent}',
      kind: _AssumptionInputKind.decimal,
    ),
    _AssumptionInput(
      key: 'inflationPercent',
      label: 'Inflation %',
      text: '${assumptions.inflationPercent}',
      kind: _AssumptionInputKind.decimal,
    ),
    _AssumptionInput(
      key: 'retirementTaxPercent',
      label: 'Retirement tax %',
      text: '${assumptions.retirementTaxPercent}',
      kind: _AssumptionInputKind.decimal,
    ),
    _AssumptionInput(
      key: 'socialSecurityMonthlyDollars',
      label: 'Social Security \$/mo from 62',
      text: '${assumptions.socialSecurityMonthlyDollars}',
      kind: _AssumptionInputKind.wholeNumber,
    ),
    _AssumptionInput(
      key: 'mortgageRatePercent',
      label: 'Mortgage rate %',
      text: '${assumptions.mortgageRatePercent}',
      kind: _AssumptionInputKind.decimal,
    ),
    _AssumptionInput(
      key: 'housingAfterPayoffMonthlyDollars',
      label: 'Housing after payoff \$/mo',
      text: '${assumptions.housingAfterPayoffMonthlyDollars}',
      kind: _AssumptionInputKind.wholeNumber,
    ),
    _AssumptionInput(
      key: 'takeHomeOverrideAnnualDollars',
      label: 'Take-home override \$/yr',
      text: '${assumptions.takeHomeOverrideAnnualDollars ?? ''}',
      kind: _AssumptionInputKind.optionalWholeNumber,
      hint: 'live',
    ),
    _AssumptionInput(
      key: 'spendingOverrideAnnualDollars',
      label: 'Non-housing spending override \$/yr',
      text: '${assumptions.spendingOverrideAnnualDollars ?? ''}',
      kind: _AssumptionInputKind.optionalWholeNumber,
      hint: 'live',
    ),
    _AssumptionInput(
      key: 'childBirthYears',
      label: 'Children (birth years)',
      text: assumptions.childBirthYears.join(', '),
      kind: _AssumptionInputKind.yearList,
      hint: 'e.g. 2027, 2030',
    ),
  ];
}

class const _AssumptionField({super.key, required final _AssumptionInput input})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AssumptionField> createState() => _AssumptionFieldState();
}

class _AssumptionFieldState() extends ConsumerState<_AssumptionField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.input.text,
  );
  late final FocusNode _focusNode = FocusNode()..addListener(_saveOnBlur);
  String? _error;

  @override
  void didUpdateWidget(_AssumptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.input.text != _controller.text) {
      _controller.text = widget.input.text;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(widget.input.label, style: EText.caption)),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textAlign: TextAlign.right,
              style: EText.caption.copyWith(color: EColors.textPrimary),
              decoration: EInput.filled(hintText: widget.input.hint)
                  .copyWith(isDense: true, errorText: _error),
              onSubmitted: (_) => _save(),
            ),
          ),
        ],
      ),
    );
  }

  void _saveOnBlur() {
    if (!_focusNode.hasFocus) _save();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text == widget.input.text) return;
    final Object? value;
    try {
      value = _parsed(text);
    } on FormatException {
      setState(() => _error = 'Not valid');
      return;
    }
    setState(() => _error = null);
    await ref.read(projectionAssumptionsEditorProvider).apply({
      widget.input.key: value,
    });
  }

  Object? _parsed(String text) => switch (widget.input.kind) {
    _AssumptionInputKind.wholeNumber => int.parse(text),
    _AssumptionInputKind.decimal => double.parse(text),
    _AssumptionInputKind.optionalWholeNumber =>
      text.isEmpty ? null : int.parse(text.replaceAll(',', '')),
    _AssumptionInputKind.optionalDay =>
      text.isEmpty ? null : DateTime.parse(text).dayKey,
    _AssumptionInputKind.yearList => [
      for (final part in text.split(','))
        if (part.trim().isNotEmpty) int.parse(part.trim()),
    ],
  };
}
