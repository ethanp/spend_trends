import 'package:ethan_utils/ethan_utils.dart';
import 'package:flutter/material.dart';

/// Picks a calendar date with a Material calendar dialog.
Future<DateTime?> pickAppDate(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? minimumDate,
  DateTime? maximumDate,

  /// [DatePickerMode.year] for dates far from today, like a birth date.
  DatePickerMode initialMode = DatePickerMode.day,
}) async {
  final firstDate = (minimumDate ?? DateTime(1970)).startOfDay;
  final lastDate = (maximumDate ?? DateTime(2100)).startOfDay;
  var initial = initialDate.startOfDay;
  if (initial.isBefore(firstDate)) initial = firstDate;
  if (initial.isAfter(lastDate)) initial = lastDate;

  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDatePickerMode: initialMode,
  );
  return picked?.startOfDay;
}
