import 'package:flutter/material.dart';

import 'app.dart';
import 'licenses/native_licenses.dart';
import 'services/ir_file_picker_service.dart';
import 'services/ir_reference_catalog_service.dart';
import 'services/usb_platform_service.dart';
import 'tone3000/tone3000_composition.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerNativeThirdPartyLicenses();
  runApp(
    WyrmToneApp(
      usbService: MethodChannelUsbService(),
      irReferenceCatalogService: const FlutterIrReferenceCatalogService(),
      irFilePickerService: MethodChannelIrFilePicker(),
      tone3000Controller: createTone3000Controller(),
    ),
  );
}
