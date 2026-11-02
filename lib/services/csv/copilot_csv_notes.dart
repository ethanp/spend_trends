import 'package:ethan_utils/ethan_utils.dart';

abstract final class CopilotCsvNotes() {
  static bool isPresent(String? note) => note.trimmedOrEmpty.isNotEmpty;
}
