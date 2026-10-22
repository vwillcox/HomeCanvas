/// Reading text out of decoded JSON and saved options.
extension MapText on Map {
  /// The value at [key] as trimmed text: empty when it is missing or null,
  /// and anything that isn't a string written out as one.
  String text(Object key) => '${this[key] ?? ''}'.trim();
}
