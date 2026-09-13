import 'package:wyrmtone/models/ir_metadata.dart';
import 'package:wyrmtone/models/ir_catalog_entry.dart';
import 'package:wyrmtone/services/ir_file_picker_service.dart';
import 'package:wyrmtone/services/ir_reference_catalog_service.dart';
import 'package:wyrmtone/services/local_persistence.dart';

class MemoryStringStore implements StringStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class FakeIrFilePicker implements IrFilePickerService {
  FakeIrFilePicker([this.files = const []]);
  List<PickedIrFile> files;
  PickedIrFolder? restoredFolder;

  @override
  Future<PickedIrFolder?> pickWavFolder() async =>
      PickedIrFolder(treeUri: 'content://tree/selected', files: files);

  @override
  Future<PickedIrFolder?> restorePersistedWavFolder() async => restoredFolder;
}

class FakeIrReferenceCatalog implements IrReferenceCatalogService {
  FakeIrReferenceCatalog([this.entries = const []]);

  List<IrCatalogEntry> entries;

  @override
  Future<List<IrCatalogEntry>> load() async => entries;
}
