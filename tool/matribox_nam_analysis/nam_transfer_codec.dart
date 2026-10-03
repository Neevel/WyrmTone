// Offline codec for the Clone (NAM) transfer -- re-exports the product copy
// in `lib/services/matribox_nam_transfer_codec.dart` so the offline analysis
// tooling and the product code share exactly one implementation (a `lib/`
// file cannot import out of `lib/`, so the promotion had to go this
// direction: `tool/` importing `lib/` via `package:wyrmtone/...`, not the
// other way around).
export 'package:wyrmtone/services/matribox_nam_transfer_codec.dart';
