// GENERATED programmatically from the original USBPcap capture by
// tool/matribox_capture_inspector.dart (no hand transcription). The
// binary capture itself is deliberately NOT in this repository.
// Selection per parameter: first, middle and last host->device message
// of that parameter's group (all messages if the group has <= 3).
library;

const matriboxStoreCaptureSource = 'matribox1_p01_store.pcapng';
const matriboxStoreCaptureSha256 =
    '35d845d3855a4dabfc1e57a4f8c53227729ff0a77282f5ab5acc4bb83169cc1c';
const matriboxStoreCaptureDirection = 'hostToDevice';

class Sol100OdCaptureFixture {
  const Sol100OdCaptureFixture({required this.field, required this.parameterIndex, required this.value, required this.sequence, required this.timestampMs, required this.length, required this.algorithmCode, required this.hex});
  final String field;
  final int parameterIndex, sequence, length, algorithmCode;
  final double value, timestampMs;
  final String hex;
}

const sol100OdCaptureFixtures = <Sol100OdCaptureFixture>[
  Sol100OdCaptureFixture(field: 'gain', parameterIndex: 0, value: 29.0, sequence: 1, timestampMs: 3731.437, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d45321210030002040700000000000700000000000000000e080401f7'),
  Sol100OdCaptureFixture(field: 'gain', parameterIndex: 0, value: 23.0, sequence: 7, timestampMs: 4439.268, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d45321210030002040700000000000700000000000000000b080401f7'),
  Sol100OdCaptureFixture(field: 'gain', parameterIndex: 0, value: 17.0, sequence: 13, timestampMs: 5484.455, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d453212100300020407000000000007000000000000000008080401f7'),
  Sol100OdCaptureFixture(field: 'presence', parameterIndex: 1, value: 51.0, sequence: 14, timestampMs: 8949.393, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d4532121003000204070000000000070001000000000000040c0402f7'),
  Sol100OdCaptureFixture(field: 'presence', parameterIndex: 1, value: 62.0, sequence: 25, timestampMs: 9920.127, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d453212100300020407000000000007000100000000000007080402f7'),
  Sol100OdCaptureFixture(field: 'presence', parameterIndex: 1, value: 73.0, sequence: 36, timestampMs: 11499.447, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d453212100300020407000000000007000100000000000009020402f7'),
  Sol100OdCaptureFixture(field: 'volume', parameterIndex: 2, value: 49.0, sequence: 66, timestampMs: 28134.720999999998, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d453212100300020407000000000007000200000000000004040402f7'),
  Sol100OdCaptureFixture(field: 'volume', parameterIndex: 2, value: 48.0, sequence: 67, timestampMs: 28467.688, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d453212100300020407000000000007000200000000000004000402f7'),
  Sol100OdCaptureFixture(field: 'volume', parameterIndex: 2, value: 47.0, sequence: 68, timestampMs: 28984.797, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d4532121003000204070000000000070002000000000000030c0402f7'),
  Sol100OdCaptureFixture(field: 'bass', parameterIndex: 3, value: 49.0, sequence: 37, timestampMs: 18108.267, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d453212100300020407000000000007000300000000000004040402f7'),
  Sol100OdCaptureFixture(field: 'bass', parameterIndex: 3, value: 35.0, sequence: 51, timestampMs: 18682.097999999998, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d4532121003000204070000000000070003000000000000000c0402f7'),
  Sol100OdCaptureFixture(field: 'bass', parameterIndex: 3, value: 23.0, sequence: 65, timestampMs: 21382.072999999997, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d45321210030002040700000000000700030000000000000b080401f7'),
  Sol100OdCaptureFixture(field: 'middle', parameterIndex: 4, value: 49.0, sequence: 69, timestampMs: 32471.102000000003, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d453212100300020407000000000007000400000000000004040402f7'),
  Sol100OdCaptureFixture(field: 'middle', parameterIndex: 4, value: 59.0, sequence: 81, timestampMs: 34150.125, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d4532121003000204070000000000070004000000000000060c0402f7'),
  Sol100OdCaptureFixture(field: 'middle', parameterIndex: 4, value: 67.0, sequence: 93, timestampMs: 37802.472, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d453212100300020407000000000007000400000000000008060402f7'),
  Sol100OdCaptureFixture(field: 'treble', parameterIndex: 5, value: 51.0, sequence: 94, timestampMs: 41994.43, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d4532121003000204070000000000070005000000000000040c0402f7'),
  Sol100OdCaptureFixture(field: 'treble', parameterIndex: 5, value: 42.0, sequence: 105, timestampMs: 42470.341, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d453212100300020407000000000007000500000000000002080402f7'),
  Sol100OdCaptureFixture(field: 'treble', parameterIndex: 5, value: 31.0, sequence: 116, timestampMs: 43912.825, length: 34, algorithmCode: 0x07000047,
      hex: 'f021257f514d45321210030002040700000000000700050000000000000f080401f7'),
];
