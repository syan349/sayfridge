import 'package:flutter/material.dart';

import '../repositories/storage_space_repository.dart';
import '../repositories/workspace_repository.dart';
import '../screens/storage_space_screen.dart';
import '../services/storage_space_api_service.dart';
import '../state/storage_space_controller.dart';

Future<void> manageStorageSpaces(
  BuildContext context,
  WorkspaceRepository workspace,
) async {
  final controller = StorageSpaceController(
    StorageSpaceRepository(
      StorageSpaceApiService(workspace.client),
      workspace.tokens,
    ),
    workspace: workspace,
  );
  await controller.loadStorageSpaces();
  if (!context.mounted) {
    controller.dispose();
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => StorageSpaceScreen(controller: controller),
    ),
  );
  controller.dispose();
}
