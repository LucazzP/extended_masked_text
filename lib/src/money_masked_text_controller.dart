import 'dart:math';

import 'package:extended_masked_text/src/common/cursor_behavior.dart';
import 'package:flutter/widgets.dart';

/// A [TextEditingController] extended to apply masks to currency values
class MoneyMaskedTextController extends TextEditingController {
  /// Creates a controller for an editable text field for currencies
  ///
  /// This constructor treats a null [initialValue] argument as if it were the
  /// empty
  ///
  /// The [decimalSeparator] and [thousandSeparator] are useful to ensure the
  /// formatted number follows the desired localization.
  ///
  /// The [rightSymbol] and [leftSymbol] are actually suffixes and prefixes and
  /// can have multiple characters
  ///
  /// [precision] is used to control the number of fraction digits
  MoneyMaskedTextController({
    double? initialValue,
    this.decimalSeparator = ',',
    this.thousandSeparator = '.',
    this.rightSymbol = '',
    this.leftSymbol = '',
    this.precision = 2,
    this.cursorBehavior = CursorBehavior.end,
  }) {
    _validateConfig();
    _shouldApplyTheMask = true;

    addListener(_listener);
    updateValue(initialValue);
  }

  /// Character used as decimal separator
  ///
  /// Defaults to ',' and must not be null.
  final String decimalSeparator;

  /// Character used as thousand separator
  ///
  /// Defaults to '.' and must not be null.
  final String thousandSeparator;

  /// Character used as right symbol
  ///
  /// Defaults to empty string. Must not be null.
  final String rightSymbol;

  /// Character used as left symbol
  ///
  /// Defaults to empty string. Must not be null.
  final String leftSymbol;

  /// Numeric precision to fraction digits
  ///
  /// Defaults to 2
  final int precision;

  /// Configure if the cursor should be forced
  final CursorBehavior cursorBehavior;

  /// The last valid numeric value
  double? _lastValue;

  /// Used to ensure that the listener will not try to update the mask when
  /// updating the text internally, thus reducing the number of operations when
  /// applying a mask (works as a mutex)
  late bool _shouldApplyTheMask;

  /// The numeric value of the text
  double get numberValue {
    final parts = _getOnlyNumbers(text).split('').toList(growable: true);

    if (parts.isEmpty) {
      return 0;
    }

    parts.insert(parts.length - precision, '.');
    return double.parse(parts.join());
  }

  static const int _maxNumLength = 12;

  /// Updates the value and applies the mask
  void updateValue(double? value) {
    if (value == null) {
      return;
    }

    double? valueToUse = value;

    if (value.toStringAsFixed(0).length > _maxNumLength) {
      valueToUse = _lastValue;
    } else {
      _lastValue = value;
    }

    final masked = _applyMask(valueToUse!);

    _updateText(masked);
  }

  /// The current value as a [String] without the mask
  String get unmasked => _removeMask(text);

  void _listener() {
    _updateCursorIfNotUnlocked();

    if (!_shouldApplyTheMask) {
      return;
    }

    var parts = _getOnlyNumbers(text).split('').toList(growable: true);

    if (parts.isNotEmpty) {
      // Ensures that the list of parts contains the minimum amount of
      // characters to fit the precision
      if (parts.length < precision + 1) {
        parts = [...List.filled(precision, '0'), ...parts];
      }

      parts.insert(parts.length - precision, '.');
      updateValue(double.parse(parts.join()));
    }
  }

  void _updateCursorIfNotUnlocked() => switch (cursorBehavior) {
        CursorBehavior.unlocked => null,
        CursorBehavior.end => _moveCursorToEnd(),
      };

  void _moveCursorToEnd() => _moveCursor(text.length - leftSymbol.length, true);

  /// Moves cursor to specific position
  void _moveCursor(int index, [bool force = false]) {
    // if the update isn't being forced and the text is selected do not move
    // the cursor
    if (!force && selection.baseOffset != selection.extentOffset) {
      return;
    }

    final value = min(max(index, 0), text.length);
    selection = TextSelection.collapsed(offset: value);
  }

  /// Updates the [TextEditingController] and ensures that the listener will
  /// not trigger the mask update
  void _updateText(String newText) {
    if (text == newText) {
      return;
    }

    _shouldApplyTheMask = false;
    final newSelection = _getNewSelection(newText);

    value = TextEditingValue(
      selection: newSelection,
      text: newText,
    );

    _shouldApplyTheMask = true;
  }

  /// Returns the updated selection with the new cursor position
  TextSelection _getNewSelection(String newText) {
    // If baseOffset differs from extentOffset, user is selecting the text,
    // then we keep the current selection
    if (selection.baseOffset != selection.extentOffset) {
      return selection;
    }

    // When cursor is at the beginning, we set the cursor right after the first
    // character after the left symbol
    if (selection.baseOffset == 0) {
      return TextSelection.fromPosition(
        TextPosition(offset: leftSymbol.length + 1),
      );
    }

    return switch (cursorBehavior) {
      CursorBehavior.unlocked => _calculateNewCursorPosition(newText),
      CursorBehavior.end => _setCursorAtEnd(newText),
    };
  }

  TextSelection _calculateNewCursorPosition(String newText) {
    // Cursor is at end of the text
    if (selection.baseOffset == text.length) {
      return _setCursorAtEnd(newText);
    }

    // Given that the cursor is not at the end of the text, then we need to
    // calculate its new position using the new masked text and the current
    // position for the unmasked text
    try {
      // We take the number of leading zeros taking into account the behavior
      // when the text has only 4 characters
      var numberOfLeadingZeros =
          text.length - int.parse(text).toString().length;
      if (numberOfLeadingZeros == 2 && text.length == 4) {
        numberOfLeadingZeros = 1;
      }

      // Then we get the substring containing the characters to be skipped so
      // that we can position the cursor properly
      final skippedString = text.substring(
        numberOfLeadingZeros,
        selection.baseOffset,
      );

      // Positions the cursor right after going through all the characters
      // that are in the skippedString
      var cursorPosition = leftSymbol.length + 1;
      if (skippedString != '') {
        for (var i = leftSymbol.length, j = 0; i < newText.length; i++) {
          if (newText[i] == skippedString[j]) {
            j++;
            cursorPosition = i + 1;
          }

          if (j == skippedString.length) {
            cursorPosition = i + 1;
            break;
          }
        }
      }

      return TextSelection.fromPosition(
        TextPosition(offset: cursorPosition),
      );
    } catch (_) {
      // If the update fails, we set the cursor at end of the text
      // TODO(LeandroNovak): Debug to find a solution for this scenario
      return _setCursorAtEnd(newText);
    }
  }

  TextSelection _setCursorAtEnd(String newText) => TextSelection.fromPosition(
        TextPosition(offset: newText.length - rightSymbol.length),
      );

  /// Ensures [rightSymbol] does not contains numbers
  void _validateConfig() {
    if (_getOnlyNumbers(rightSymbol).isNotEmpty) {
      throw ArgumentError('rightSymbol must not have numbers.');
    }
  }

  String _getOnlyNumbers(String text) => text.replaceAll(RegExp(r'[^\d]'), '');

  /// Returns a masked String applying the mask to the value
  String _applyMask(double value) {
    final textRepresentation = value
        .toStringAsFixed(precision)
        .replaceAll('.', '')
        .split('')
        .reversed
        .toList(growable: true);

    // ignore: cascade_invocations
    textRepresentation.insert(precision, decimalSeparator);

    for (var i = precision + 4; textRepresentation.length > i; i += 4) {
      if (textRepresentation.length > i) {
        textRepresentation.insert(i, thousandSeparator);
      }
    }

    var masked = textRepresentation.reversed.join('');

    if (rightSymbol.isNotEmpty) {
      masked += rightSymbol;
    }

    if (leftSymbol.isNotEmpty) {
      masked = leftSymbol + masked;
    }

    return masked;
  }

  String _removeMask(String text) =>
      text.replaceAll(leftSymbol, '').trim().replaceAll(rightSymbol, '').trim();
}
