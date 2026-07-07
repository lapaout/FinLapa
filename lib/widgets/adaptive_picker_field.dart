import 'package:flutter/material.dart';

class PickerOption<T> {
  final T? value;
  final String label;

  const PickerOption({required this.value, required this.label});
}

class _PickerSelection<T> {
  final T? value;

  const _PickerSelection(this.value);
}

/// Dropdown for short lists; searchable bottom sheet when there are more than
/// [AdaptivePickerField.searchThreshold] meaningful (non-null) options.
class AdaptivePickerField<T> extends StatelessWidget {
  static const int searchThreshold = 10;

  final T? value;
  final List<PickerOption<T>> options;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final String? hintText;

  const AdaptivePickerField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.decoration,
    this.hintText,
  });

  int get _meaningfulOptionCount =>
      options.where((option) => option.value != null).length;

  bool get _useSearch => _meaningfulOptionCount > searchThreshold;

  PickerOption<T>? get _selectedOption {
    for (final option in options) {
      if (option.value == value) {
        return option;
      }
    }
    return null;
  }

  bool get _hasSelectedValue => value != null && _selectedOption != null;

  @override
  Widget build(BuildContext context) {
    if (!_useSearch) {
      return DropdownButtonFormField<T?>(
        value: _hasSelectedValue ? value : null,
        decoration: decoration,
        hint: hintText != null ? Text(hintText!) : null,
        isExpanded: true,
        items: options
            .map(
              (option) => DropdownMenuItem<T?>(
                value: option.value,
                child: Text(
                  option.label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      );
    }

    return InkWell(
      onTap: onChanged == null ? null : () => _openSearchSheet(context),
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: decoration.copyWith(
          suffixIcon: const Icon(Icons.arrow_drop_down),
          hintText: _hasSelectedValue ? null : hintText,
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
        isEmpty: !_hasSelectedValue,
        child: _hasSelectedValue
            ? Text(
                _selectedOption!.label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              )
            : const SizedBox(height: 24),
      ),
    );
  }

  Future<void> _openSearchSheet(BuildContext context) async {
    final result = await showModalBottomSheet<_PickerSelection<T>?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SearchPickerSheet<T>(
        options: options,
        hintText: hintText,
      ),
    );

    if (result != null) {
      onChanged?.call(result.value);
    }
  }
}

class _SearchPickerSheet<T> extends StatefulWidget {
  final List<PickerOption<T>> options;
  final String? hintText;

  const _SearchPickerSheet({
    required this.options,
    this.hintText,
  });

  @override
  State<_SearchPickerSheet<T>> createState() => _SearchPickerSheetState<T>();
}

class _SearchPickerSheetState<T> extends State<_SearchPickerSheet<T>> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PickerOption<T>> get _filteredOptions {
    final normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return widget.options;
    }

    return widget.options
        .where(
          (option) => option.label.toLowerCase().contains(normalizedQuery),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final filteredOptions = _filteredOptions;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: widget.hintText ?? 'Пошук...',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Flexible(
              child: filteredOptions.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Нічого не знайдено',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredOptions.length,
                      itemBuilder: (context, index) {
                        final option = filteredOptions[index];
                        return ListTile(
                          title: Text(
                            option.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.pop(
                              context,
                              _PickerSelection<T>(option.value),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
