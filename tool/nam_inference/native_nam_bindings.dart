// Raw dart:ffi bindings to the native NAM bridge -- re-exports the product
// copy in `lib/services/nam_native_bindings.dart` (Android NAM Inference V1)
// so the Windows offline research tooling and the Android product app share
// exactly one FFI binding, never two.
export 'package:wyrmtone/services/nam_native_bindings.dart';
