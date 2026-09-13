class ParsedMidiMessage {
  ParsedMidiMessage(this.bytes, this.type, this.status);
  final List<int> bytes;
  final String type;
  final String status;
}

/// Structural classification only. Real-Time bytes never enter the SysEx buffer.
class MidiParser {
  MidiParser({this.maxSysExBytes = 65536, this.timeoutMillis = 2000});
  final int maxSysExBytes;
  final int timeoutMillis;
  final List<int> _sysex = [];
  final List<int> _pending = [];
  int? _runningStatus;
  int? _lastFragmentMillis;
  bool _discarding = false;
  bool get sysExPending => _sysex.isNotEmpty;
  bool get incompletePending => _sysex.isNotEmpty || _pending.isNotEmpty;
  int get bufferedBytes => _sysex.length + _pending.length;
  List<ParsedMidiMessage> feed(List<int> bytes, int nowMillis) {
    final messages = expire(nowMillis);
    for (final byte in bytes) {
      if (byte >= 0xF8) {
        messages.add(
          ParsedMidiMessage([byte], 'System Real-Time', 'vollständig'),
        );
        continue;
      }
      if (_discarding && byte != 0xF0) {
        if (byte == 0xF7) _discarding = false;
        continue;
      }
      if (_sysex.isNotEmpty) {
        if (byte == 0xF7 || byte < 0x80) {
          if (_sysex.length >= maxSysExBytes) {
            messages.add(
              ParsedMidiMessage(
                List.of(_sysex),
                'SysEx',
                'verworfen: Größenlimit',
              ),
            );
            _sysex.clear();
            _discarding = byte != 0xF7;
          } else {
            _sysex.add(byte);
            _lastFragmentMillis = nowMillis;
            if (byte == 0xF7) {
              messages.add(
                ParsedMidiMessage(List.of(_sysex), 'SysEx', 'vollständig'),
              );
              _sysex.clear();
            }
          }
          continue;
        }
        messages.add(
          ParsedMidiMessage(
            List.of(_sysex),
            'SysEx',
            'unvollständig: neuer Status',
          ),
        );
        _sysex.clear();
      }
      if (byte >= 0x80) {
        if (_pending.isNotEmpty) {
          messages.add(
            ParsedMidiMessage(
              List.of(_pending),
              'unbekannt/unvollständig',
              'unvollständig',
            ),
          );
          _pending.clear();
        }
        if (byte == 0xF0) {
          _discarding = false;
          _runningStatus = null;
          _sysex.add(byte);
          _lastFragmentMillis = nowMillis;
          continue;
        }
        _runningStatus = byte < 0xF0 ? byte : null;
        _pending.add(byte);
      } else {
        if (_pending.isEmpty && _runningStatus != null) {
          _pending.add(_runningStatus!);
        }
        if (_pending.isEmpty) {
          messages.add(
            ParsedMidiMessage([byte], 'unbekannt/unvollständig', 'unbekannt'),
          );
          continue;
        }
        _pending.add(byte);
      }
      if (_pending.length >= _messageLength(_pending.first)) {
        final type = _type(_pending.first);
        messages.add(
          ParsedMidiMessage(
            List.of(_pending),
            type,
            type == 'unbekannt/unvollständig' ? 'unbekannt' : 'vollständig',
          ),
        );
        _pending.clear();
      }
    }
    return messages;
  }

  List<ParsedMidiMessage> expire(int nowMillis) {
    if (_sysex.isEmpty ||
        nowMillis - (_lastFragmentMillis ?? nowMillis) < timeoutMillis) {
      return [];
    }
    final message = ParsedMidiMessage(
      List.of(_sysex),
      'SysEx',
      'unvollständig: Timeout',
    );
    _sysex.clear();
    _discarding = true;
    return [message];
  }

  List<ParsedMidiMessage> finish() {
    final messages = <ParsedMidiMessage>[];
    if (_sysex.isNotEmpty) {
      messages.add(
        ParsedMidiMessage(List.of(_sysex), 'SysEx', 'unvollständig: beendet'),
      );
    }
    if (_pending.isNotEmpty) {
      messages.add(
        ParsedMidiMessage(
          List.of(_pending),
          'unbekannt/unvollständig',
          'unvollständig: beendet',
        ),
      );
    }
    _sysex.clear();
    _pending.clear();
    _runningStatus = null;
    _discarding = false;
    _lastFragmentMillis = null;
    return messages;
  }

  static int _messageLength(int status) {
    if (status < 0xF0) return status >> 4 == 0xC || status >> 4 == 0xD ? 2 : 3;
    return switch (status) {
      0xF1 || 0xF3 => 2,
      0xF2 => 3,
      _ => 1,
    };
  }

  static String _type(int status) => switch (status >> 4) {
    0x8 => 'Note Off',
    0x9 => 'Note On',
    0xA => 'Polyphonic Aftertouch',
    0xB => 'Control Change',
    0xC => 'Program Change',
    0xD => 'Channel Pressure',
    0xE => 'Pitch Bend',
    _ =>
      [0xF1, 0xF2, 0xF3, 0xF6].contains(status)
          ? 'System Common'
          : 'unbekannt/unvollständig',
  };
}
