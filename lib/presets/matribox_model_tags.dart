/// Small semantic metadata layer on top of the editor catalog. It is NOT a
/// second model list: the catalog (181 algorithms) stays the source of names,
/// codes and parameters. Tags only say what a model is FOR, derived from
/// model names and general amp/pedal families, and are DEVICE_APPROXIMATION
/// knowledge -- never a claim about original recording equipment.
///
/// Models without tags are simply not selectable by the matcher yet (the
/// report says so); tagging can grow model by model.
library;

class ModelTags {
  const ModelTags(this.tags, {this.gainCenter, this.tightnessCenter, this.midsCenter});

  /// Free tags: pedal kind (`boost`, `overdrive`, ...), delay/reverb/
  /// modulation type, amp family (`british`), gate flavour.
  final Set<String> tags;

  /// Amp models only: the perceptual centre (0..100) the model suits best.
  /// Sol 100 OD/LD reuse the centres of the existing offline engine.
  final int? gainCenter, tightnessCenter, midsCenter;
}

const matriboxModelTags = <String, ModelTags>{
  // pre-amp position (FX1/FX2)
  'Boost': ModelTags({'boost', 'tight'}),
  'Skreamer': ModelTags({'overdrive', 'tight'}),
  'Super OD': ModelTags({'overdrive'}),
  'Butter OD': ModelTags({'overdrive', 'warm'}),
  'Blues OD': ModelTags({'overdrive', 'warm'}),
  'Dist Plus': ModelTags({'distortion'}),
  'JP Dist': ModelTags({'distortion'}),
  'Shark': ModelTags({'distortion'}),
  'Dark Mouse': ModelTags({'distortion'}),
  'Fuzz Cream': ModelTags({'fuzz'}),
  'Red Fuzz': ModelTags({'fuzz'}),
  'COMP': ModelTags({'compressor'}),
  'COMP2': ModelTags({'compressor'}),
  'Octaver': ModelTags({'octave'}),
  'Touch-W': ModelTags({'wah'}),
  'Auto-W': ModelTags({'wah'}),
  'UK-W': ModelTags({'wah'}),
  'Cry-W': ModelTags({'wah'}),
  // amps
  'Sol 100 OD': ModelTags({'highGain', 'modern'}, gainCenter: 65, tightnessCenter: 78, midsCenter: 65),
  'Sol 100 LD': ModelTags({'highGain', 'modern'}, gainCenter: 80, tightnessCenter: 78, midsCenter: 65),
  'Brit 800': ModelTags({'british', 'crunch'}, gainCenter: 55, tightnessCenter: 60, midsCenter: 70),
  'TWD Deluxe': ModelTags({'clean', 'vintage'}, gainCenter: 25, tightnessCenter: 35, midsCenter: 55),
  'Calif Star CL': ModelTags({'clean'}, gainCenter: 20, tightnessCenter: 45, midsCenter: 50),
  // gates
  'Gate 1': ModelTags({'simple'}),
  'Gate 2': ModelTags({'adjustable'}),
  // EQ
  'Guitar EQ': ModelTags({'guitar'}),
  'Bass EQ': ModelTags({'bass'}),
  // modulation
  'Chorus A': ModelTags({'chorus'}),
  'Chorus B': ModelTags({'chorus'}),
  'Flanger': ModelTags({'flanger'}),
  'Phaser': ModelTags({'phaser'}),
  'Tremolo': ModelTags({'tremolo'}),
  'Sine Trem': ModelTags({'tremolo'}),
  'Bias Trem': ModelTags({'tremolo'}),
  // delay
  'Pure': ModelTags({'digital'}),
  'Warm': ModelTags({'analog'}),
  'Tube': ModelTags({'analog'}),
  'Tape': ModelTags({'tape'}),
  'Ping Pong': ModelTags({'pingPong'}),
  'Sweep': ModelTags({'modulated'}),
  // reverb
  'Room': ModelTags({'room'}),
  'Hall': ModelTags({'hall'}),
  'Plate': ModelTags({'plate'}),
  'Spring': ModelTags({'spring'}),
  'Mod RVB': ModelTags({'modulated'}),
};
