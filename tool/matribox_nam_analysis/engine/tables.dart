// Re-exports the product copy in `lib/services/matribox_nam_clodata/engine/tables.dart`
// (Android NAM Inference V1 gap-closing milestone) so the offline analysis
// tooling and on-device Android CloData generation share exactly one
// implementation, never two. The frozen V4 estimator algorithm itself is
// UNCHANGED -- this is a promotion (move + re-export), not a rewrite.
export 'package:wyrmtone/services/matribox_nam_clodata/engine/tables.dart';
