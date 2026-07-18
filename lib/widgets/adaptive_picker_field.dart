import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/ui_helpers.dart';

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
        initialValue: _hasSelectedValue ? value : null,
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null ? null : () => _openSearchSheet(context),
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
    final result = await showFinLapaBottomSheet<_PickerSelection<T>?>(
      context: context,
      isScrollControlled: true,
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
  final FocusNode _searchFocusNode = FocusNode();
  late final ValueNotifier<List<PickerOption<T>>> _visibleOptionsNotifier;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _visibleOptionsNotifier = ValueNotifier(
      List<PickerOption<T>>.from(widget.options),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _visibleOptionsNotifier.dispose();
    super.dispose();
  }

  List<PickerOption<T>> _computeVisibleOptions(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return List<PickerOption<T>>.from(widget.options);
    }

    return widget.options
        .where(
          (option) => option.label.toLowerCase().contains(normalizedQuery),
        )
        .toList();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _visibleOptionsNotifier.value = _computeVisibleOptions(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.55;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: widget.hintText ?? 'Пошук...',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<List<PickerOption<T>>>(
                  valueListenable: _visibleOptionsNotifier,
                  builder: (context, visibleOptions, _) {
                    if (visibleOptions.isEmpty) {
                      return const Center(
                        child: Text(
                          'Нічого не знайдено',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: visibleOptions.length,
                      addAutomaticKeepAlives: false,
                      itemBuilder: (context, index) {
                        final option = visibleOptions[index];
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
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
