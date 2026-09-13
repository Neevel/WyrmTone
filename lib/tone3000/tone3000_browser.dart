import 'dart:async';

import 'package:flutter/services.dart';

abstract interface class Tone3000Browser {
  Stream<Uri> get callbacks;
  Future<void> open(Uri authorizationUri);
}

class PlatformTone3000Browser implements Tone3000Browser {
  PlatformTone3000Browser({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('de.neevel.wyrmtone/tone3000_oauth') {
    _channel.setMethodCallHandler(_handleMethod);
    unawaited(_channel.invokeMethod<void>('startListening'));
  }

  final MethodChannel _channel;
  final _callbacks = StreamController<Uri>.broadcast();

  @override
  Stream<Uri> get callbacks => _callbacks.stream;

  @override
  Future<void> open(Uri authorizationUri) => _channel.invokeMethod<void>(
    'openAuthorization',
    {'url': authorizationUri.toString()},
  );

  Future<void> _handleMethod(MethodCall call) async {
    if (call.method != 'oauthCallback') return;
    final encoded = call.arguments as String?;
    if (encoded != null) _callbacks.add(Uri.parse(encoded));
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _callbacks.close();
  }
}

class EmptyTone3000Browser implements Tone3000Browser {
  const EmptyTone3000Browser();

  @override
  Stream<Uri> get callbacks => const Stream.empty();

  @override
  Future<void> open(Uri authorizationUri) async {}
}
