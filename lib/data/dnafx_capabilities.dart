import '../models/dnafx_capabilities.dart';

/// Deliberately small: only names and parameters confirmed by the brief.
const confirmedDnafxCapabilities = DnafxCapabilities(
  ampModels: {'J900'},
  effectModels: {'PURE BOOST'},
  parameterNames: {
    'GAIN',
    'BASS',
    'MID',
    'TREBLE',
    'PRESENCE',
    'NOISE_GATE_ATTACK',
  },
);
