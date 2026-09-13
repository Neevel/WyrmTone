import 'package:wyrmtone/services/ir_reference_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'metadata catalog contains 210 references and known duplicates',
    () async {
      final entries = await const FlutterIrReferenceCatalogService().load();

      expect(entries, hasLength(210));
      expect(
        entries.where((entry) => entry.duplicateGroup != null),
        hasLength(6),
      );
      expect(entries.every((entry) => entry.metadata.uri == null), isTrue);
      expect(entries.every((entry) => entry.format.container == 'WAV'), isTrue);
    },
  );
}
