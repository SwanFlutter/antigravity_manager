import 'package:flutter/material.dart';
import 'package:get_x_master/get_x_master.dart';

import '../../../core/data/mock_data.dart';
import '../../../data/accounts_repository.dart';
import '../../app/controller/app_controller.dart';

/// State of the workspaces screen.
class WorkspacesController extends GetXController {
  WorkspacesController({AccountsRepository? repository})
      : repository = repository ?? defaultAccountsRepository();

  final AccountsRepository repository;

  final RxList<Workspace> workspaces = MockData.workspaces.obs;
  final RxString query = ''.obs;
  final TextEditingController searchController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    loadWorkspaces();
    // The host may still be starting; reload once it answers.
    ever(Get.find<AppController>().hostReady, (_) => loadWorkspaces());
  }

  /// Reads the workspaces from the repository.
  Future<void> loadWorkspaces() async {
    try {
      final items = await repository.workspaces();
      if (items.isNotEmpty) workspaces.assignAll(items);
    } catch (_) {
      // The screen keeps its placeholder state.
    }
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  List<Workspace> get visibleWorkspaces {
    final needle = query.value.trim().toLowerCase();
    if (needle.isEmpty) return workspaces;
    return workspaces
        .where((workspace) =>
            workspace.name.toLowerCase().contains(needle) ||
            workspace.accountName.toLowerCase().contains(needle) ||
            workspace.projectFolder.toLowerCase().contains(needle))
        .toList();
  }

  int get runningCount =>
      workspaces.where((w) => w.state == WorkspaceState.running).length;

  void launch(Workspace workspace) {
    final index = workspaces.indexWhere((w) => w.id == workspace.id);
    if (index == -1) return;
    final updated = Workspace(
      id: workspace.id,
      name: workspace.name,
      accountName: workspace.accountName,
      plan: workspace.plan,
      projectFolder: workspace.projectFolder,
      profileFolder: workspace.profileFolder,
      lastActive: workspace.lastActive,
      state: workspace.state == WorkspaceState.running
          ? WorkspaceState.stopped
          : WorkspaceState.running,
      unbound: workspace.unbound,
    );
    workspaces[index] = updated;
  }
}
