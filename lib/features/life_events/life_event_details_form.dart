import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';
import 'package:spend_trends/domain/life_event.dart';

/// The fields every life event shares, as entered in the form.
class const LifeEventBasics({
  required final String id,
  required final String title,
  required final DateTime startedOn,
  required final DateTime? endedOn,
  required final String? note,
});

/// One kind's own fields in the life-event form, and the event they make.
/// Owns its text controllers; call [dispose] when the form closes or the
/// kind changes.
sealed class LifeEventDetailsForm {
  factory forKind(LifeEventKind kind, {LifeEvent? lifeEvent}) => switch (kind) {
    LifeEventKind.milestone || LifeEventKind.childBirth => _NoDetailsForm(kind),
    LifeEventKind.job => _JobDetailsForm(lifeEvent is Job ? lifeEvent : null),
    LifeEventKind.home => _HomeDetailsForm(
      lifeEvent is HomeOwnership ? lifeEvent : null,
    ),
  };

  /// Rows under the shared fields; [rebuild] redraws after a toggle.
  List<Widget> fields(VoidCallback rebuild);

  /// Throws [FormatException] naming the field that is not a number.
  LifeEvent eventWith(LifeEventBasics basics);

  void dispose();
}

class _NoDetailsForm(final LifeEventKind kind) implements LifeEventDetailsForm {
  @override
  List<Widget> fields(VoidCallback rebuild) => const [];

  @override
  LifeEvent eventWith(LifeEventBasics basics) => switch (kind) {
    LifeEventKind.childBirth => ChildBirth(
      id: basics.id,
      title: basics.title,
      startedOn: basics.startedOn,
      endedOn: basics.endedOn,
      note: basics.note,
    ),
    _ => Milestone(
      id: basics.id,
      title: basics.title,
      startedOn: basics.startedOn,
      endedOn: basics.endedOn,
      note: basics.note,
    ),
  };

  @override
  void dispose() {}
}

class _JobDetailsForm(Job? job) implements LifeEventDetailsForm {
  final _salary = _NumberInput(
    'Take-home salary \$/yr',
    job?.takeHomeSalaryAnnual,
  );
  final _bonus = _NumberInput(
    'Take-home bonus \$/yr',
    job?.takeHomeBonusAnnual,
  );

  @override
  List<Widget> fields(VoidCallback rebuild) => [_salary.row(), _bonus.row()];

  @override
  LifeEvent eventWith(LifeEventBasics basics) => Job(
    id: basics.id,
    title: basics.title,
    startedOn: basics.startedOn,
    endedOn: basics.endedOn,
    note: basics.note,
    takeHomeSalaryAnnual: _salary.wholeNumber,
    takeHomeBonusAnnual: _bonus.wholeNumber,
  );

  @override
  void dispose() {
    _salary.dispose();
    _bonus.dispose();
  }
}

class _HomeDetailsForm(HomeOwnership? home) implements LifeEventDetailsForm {
  final _price = _NumberInput('Price \$', home?.price);
  final _downPayment = _NumberInput('Down payment \$', home?.downPayment);
  bool _isFinanced = home == null || home.mortgage != null;
  final _mortgageRate = _NumberInput(
    'Mortgage rate %',
    home?.mortgage?.ratePercent,
  );
  final _mortgageYears = _NumberInput(
    'Mortgage years',
    home?.mortgage?.years ?? 30,
  );
  bool _hasEscrow = home?.mortgage?.hasEscrow ?? false;
  final _insurance = _NumberInput('Insurance \$/yr', home?.insuranceAnnual);
  final _hoa = _NumberInput('HOA \$/yr', home?.hoaAnnual);
  final _maintenance = _NumberInput(
    'Maintenance % of value/yr',
    home?.maintenancePercent ?? 2,
  );
  final _propertyTax = _NumberInput(
    'Property tax % of value/yr',
    home?.propertyTaxPercent,
  );

  @override
  List<Widget> fields(VoidCallback rebuild) => [
    _price.row(),
    _toggle('Mortgage', _isFinanced, (isFinanced) {
      _isFinanced = isFinanced;
      rebuild();
    }),
    if (_isFinanced) ...[
      _downPayment.row(),
      _mortgageRate.row(),
      _mortgageYears.row(),
      _toggle('Escrow (tax and insurance via servicer)', _hasEscrow, (
        hasEscrow,
      ) {
        _hasEscrow = hasEscrow;
        rebuild();
      }),
    ],
    _insurance.row(),
    _hoa.row(),
    _maintenance.row(),
    _propertyTax.row(),
  ];

  @override
  LifeEvent eventWith(LifeEventBasics basics) => HomeOwnership(
    id: basics.id,
    title: basics.title,
    startedOn: basics.startedOn,
    endedOn: basics.endedOn,
    note: basics.note,
    price: _price.wholeNumber,
    downPayment: _isFinanced ? _downPayment.wholeNumber : _price.wholeNumber,
    mortgage: _isFinanced
        ? Mortgage(
            ratePercent: _mortgageRate.decimal,
            years: _mortgageYears.wholeNumber,
            hasEscrow: _hasEscrow,
          )
        : null,
    insuranceAnnual: _insurance.wholeNumber,
    hoaAnnual: _hoa.wholeNumber,
    maintenancePercent: _maintenance.decimal,
    propertyTaxPercent: _propertyTax.decimal,
  );

  Widget _toggle(String label, bool isOn, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label, style: EText.caption)),
        Switch(value: isOn, onChanged: onChanged),
      ],
    );
  }

  @override
  void dispose() {
    for (final input in [
      _price,
      _downPayment,
      _mortgageRate,
      _mortgageYears,
      _insurance,
      _hoa,
      _maintenance,
      _propertyTax,
    ]) {
      input.dispose();
    }
  }
}

/// A labeled number field; blank reads as 0.
class _NumberInput(final String label, num? initialValue) {
  final TextEditingController _controller = TextEditingController(
    text: initialValue?.toString() ?? '',
  );

  int get wholeNumber => _parsed(int.parse);

  double get decimal => _parsed(double.parse);

  T _parsed<T extends num>(T Function(String) parse) {
    final text = _controller.text.replaceAll(',', '').trim();
    if (text.isEmpty) return parse('0');
    try {
      return parse(text);
    } on FormatException {
      throw FormatException('$label is not a number.');
    }
  }

  Widget row() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: EText.caption)),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _controller,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: EText.caption.copyWith(color: EColors.textPrimary),
              decoration: EInput.filled().copyWith(isDense: true),
            ),
          ),
        ],
      ),
    );
  }

  void dispose() => _controller.dispose();
}
