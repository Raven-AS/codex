import 'dart:convert';

class StompFrame {
  const StompFrame(this.command, this.headers, this.body);
  final String command, body;
  final Map<String, String> headers;
}

String _escape(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('\r', '\\r')
    .replaceAll('\n', '\\n')
    .replaceAll(':', '\\c');
String _unescape(String value) {
  final out = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    if (value[i] != '\\') {
      out.write(value[i]);
      continue;
    }
    if (++i >= value.length) {
      throw const FormatException('Invalid STOMP escape');
    }
    out.write(switch (value[i]) {
      'n' => '\n',
      'r' => '\r',
      'c' => ':',
      '\\' => '\\',
      _ => throw const FormatException('Invalid STOMP escape'),
    });
  }
  return out.toString();
}

String encodeStomp(
  String command,
  Map<String, String> headers, {
  String body = '',
}) {
  if (!RegExp(r'^[A-Z]+$').hasMatch(command)) {
    throw const FormatException('Invalid STOMP command');
  }
  final out = StringBuffer('$command\n');
  for (final entry in headers.entries) {
    if (entry.key.contains('\u0000') || entry.value.contains('\u0000')) {
      throw const FormatException('Invalid STOMP header');
    }
    if (command == 'CONNECT') {
      if (entry.key.contains(RegExp(r'[:\r\n]')) ||
          entry.value.contains(RegExp(r'[\r\n]'))) {
        throw const FormatException('Invalid CONNECT header');
      }
      out.writeln('${entry.key}:${entry.value}');
    } else {
      out.writeln('${_escape(entry.key)}:${_escape(entry.value)}');
    }
  }
  if (body.isNotEmpty) {
    out.writeln('content-length:${utf8.encode(body).length}');
  }
  return '${out.toString()}\n$body\u0000';
}

/// STOMP 1.2 byte lengths, fragmentation, multiple frames, and heartbeat lines.
class StompDecoder {
  final _bytes = <int>[];
  void clear() => _bytes.clear();
  List<StompFrame> add(String value) {
    _bytes.addAll(utf8.encode(value));
    if (_bytes.length > 1024 * 1024) {
      throw const FormatException('STOMP frame too large');
    }
    final frames = <StompFrame>[];
    while (_bytes.isNotEmpty) {
      while (_bytes.isNotEmpty && (_bytes.first == 10 || _bytes.first == 13)) {
        _bytes.removeAt(0);
      }
      if (_bytes.isEmpty) break;
      var pos = 0;
      String? line() {
        final end = _bytes.indexOf(10, pos);
        if (end < 0) return null;
        final result = utf8.decode(
          _bytes.sublist(
            pos,
            end > pos && _bytes[end - 1] == 13 ? end - 1 : end,
          ),
        );
        pos = end + 1;
        return result;
      }

      final command = line();
      if (command == null) break;
      final headers = <String, String>{};
      var complete = true;
      while (true) {
        final header = line();
        if (header == null) {
          complete = false;
          break;
        }
        if (header.isEmpty) break;
        final colon = header.indexOf(':');
        if (colon <= 0) {
          throw const FormatException('Invalid STOMP header');
        }
        final key = command == 'CONNECTED'
            ? header.substring(0, colon)
            : _unescape(header.substring(0, colon));
        final content = command == 'CONNECTED'
            ? header.substring(colon + 1)
            : _unescape(header.substring(colon + 1));
        headers.putIfAbsent(key, () => content);
      }
      if (!complete) break;
      int end;
      if (headers.containsKey('content-length')) {
        final length = int.tryParse(headers['content-length']!);
        if (length == null || length < 0 || length > 1024 * 1024) {
          throw const FormatException('Invalid STOMP length');
        }
        end = pos + length;
        if (_bytes.length <= end) break;
        if (_bytes[end] != 0) {
          throw const FormatException('Missing STOMP terminator');
        }
      } else {
        end = _bytes.indexOf(0, pos);
        if (end < 0) break;
      }
      frames.add(
        StompFrame(
          command,
          Map.unmodifiable(headers),
          utf8.decode(_bytes.sublist(pos, end)),
        ),
      );
      _bytes.removeRange(0, end + 1);
    }
    return frames;
  }
}

/// Actual SockJS WebSocket frames; XHR/streaming/polling are not implemented.
List<String> sockJsMessages(String frame) {
  if (!frame.startsWith('a')) {
    throw const FormatException('Expected SockJS message array');
  }
  final values = jsonDecode(frame.substring(1));
  if (values is! List || values.any((value) => value is! String)) {
    throw const FormatException('Invalid SockJS array');
  }
  return values.cast<String>();
}
