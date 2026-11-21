import 'package:ethan_ui/ethan_ui.dart';
import 'package:material_ui/material_ui.dart';

/// Select all / Select none shortcuts for multi-select match lists.
class const SelectAllNoneRow({
  required final VoidCallback onAllSelected,
  required final VoidCallback onNoneSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: ELayout.spaceMd,
      runSpacing: ELayout.spaceXs,
      children: [
        TextButton(
          onPressed: onAllSelected,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: ELayout.spaceSm),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Select all'),
        ),
        TextButton(
          onPressed: onNoneSelected,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: ELayout.spaceSm),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Select none'),
        ),
      ],
    );
  }
}
