// Product-facing NAM inference engine -- re-exports the product copy in
// `lib/services/nam_inference_engine.dart` (Android NAM Inference V1) so the
// Windows offline research tooling and the Android product app share
// exactly one engine/error-mapping implementation, never two.
export 'package:wyrmtone/services/nam_inference_engine.dart';
