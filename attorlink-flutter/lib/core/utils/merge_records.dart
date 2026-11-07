/// Offset pages can overlap while the server's ordering changes. Keep one row
/// per identity, adopting the latest returned fields without moving old rows.
List<T> mergeRecords<T>(
  Iterable<T> current,
  Iterable<T> incoming, {
  required Object Function(T) identity,
  bool Function(T)? retain,
}) {
  final records = {for (final item in current) identity(item): item};
  for (final item in incoming) {
    final key = identity(item);
    if (retain != null && !retain(item)) {
      records.remove(key);
    } else {
      records[key] = item;
    }
  }
  return records.values.toList();
}
