/// Type-safe variant wrapper for modifier values.
///
/// Replaces `dynamic` with explicit type discrimination.
/// All modifier values wrapped in appropriate subtype.
///
/// Part of M8 Modifiers (Phase 6).
sealed class ModifierValue {
  const ModifierValue();
}

/// Integer modifier value.
class IntModifierValue extends ModifierValue {
  final int value;

  const IntModifierValue(this.value);

  @override
  String toString() => 'IntModifierValue($value)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IntModifierValue &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Double modifier value.
class DoubleModifierValue extends ModifierValue {
  final double value;

  const DoubleModifierValue(this.value);

  @override
  String toString() => 'DoubleModifierValue($value)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DoubleModifierValue &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// String modifier value.
class StringModifierValue extends ModifierValue {
  final String value;

  const StringModifierValue(this.value);

  @override
  String toString() => 'StringModifierValue($value)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StringModifierValue &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Boolean modifier value.
class BoolModifierValue extends ModifierValue {
  final bool value;

  const BoolModifierValue(this.value);

  @override
  String toString() => 'BoolModifierValue($value)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoolModifierValue &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}
