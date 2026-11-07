/// Expand scientific JSON numbers for form input without rounding precision.
String decimalText(Object? value) {
  if (value == null) return '';
  final text = value.toString();
  if (value is! num || !text.toLowerCase().contains('e')) return text;
  final parts = text.toLowerCase().split('e');
  final negative = parts[0].startsWith('-');
  final coefficient = negative ? parts[0].substring(1) : parts[0];
  final point = coefficient.contains('.')
      ? coefficient.indexOf('.')
      : coefficient.length;
  final digits = coefficient.replaceAll('.', '');
  final position = point + int.parse(parts[1]);
  final expanded = position <= 0
      ? '0.${'0' * -position}$digits'
      : position >= digits.length
      ? '$digits${'0' * (position - digits.length)}'
      : '${digits.substring(0, position)}.${digits.substring(position)}';
  return '${negative ? '-' : ''}$expanded';
}
