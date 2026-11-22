import 'package:flutter/material.dart';

import '../uploads/upload_history_page.dart';
import '../uploads/upload_history_repository.dart';

class AdminUploadsPage extends StatelessWidget {
  const AdminUploadsPage({super.key, required this.repository});

  final UploadHistoryRepository repository;

  @override
  Widget build(BuildContext context) =>
      UploadHistoryPage(repository: repository, allUsers: true);
}
