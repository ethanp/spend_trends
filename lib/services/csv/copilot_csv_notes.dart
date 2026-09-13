abstract final class CopilotCsvNotes() {
  static bool isPresent(String? note) => (note?.trim() ?? '').isNotEmpty;
}
