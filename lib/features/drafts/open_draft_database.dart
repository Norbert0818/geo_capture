import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_web/sembast_web.dart';

Future<Database> openDraftDatabase() async {
  if (kIsWeb) {
    return databaseFactoryWeb.openDatabase('geocapture_drafts_v1');
  }
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return databaseFactoryIo.openDatabase(
    '${directory.path}/geocapture_drafts_v1.db',
  );
}