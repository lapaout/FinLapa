import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/repositories/workspace_repository.dart';
import '../data/sources/google_api_auth.dart';
import '../models/finlapa_spreadsheet.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

/// Після входу: відновлення сесії або onboarding, потім HomeScreen.
class AuthenticatedShell extends StatefulWidget {
  final GoogleSignInAccount user;
  final GoogleSignIn googleSignIn;

  const AuthenticatedShell({
    super.key,
    required this.user,
    required this.googleSignIn,
  });

  @override
  State<AuthenticatedShell> createState() => _AuthenticatedShellState();
}

class _AuthenticatedShellState extends State<AuthenticatedShell> {
  final WorkspaceRepository _workspaceRepository = WorkspaceRepository();

  bool _isBootstrapping = true;
  FinLapaSpreadsheet? _activeWorkspace;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await GoogleApiAuth.ensureScopesGranted();
      final session = await _workspaceRepository.resolveInitialWorkspace(
        user: widget.user,
      );
      if (!mounted) return;
      setState(() {
        _activeWorkspace = session;
        _isBootstrapping = false;
      });
    } catch (error) {
      debugPrint('AuthenticatedShell bootstrap error: $error');
      final cachedId = await _workspaceRepository.readCachedWorkspaceId();
      if (!mounted) return;
      if (cachedId != null) {
        final cachedName =
            await _workspaceRepository.readCachedWorkspaceName() ?? 'Таблиця';
        setState(() {
          _activeWorkspace = FinLapaSpreadsheet(id: cachedId, name: cachedName);
          _isBootstrapping = false;
        });
        return;
      }
      setState(() => _isBootstrapping = false);
    }
  }

  Future<void> _completeWorkspaceSelection(FinLapaSpreadsheet workspace) async {
    await _workspaceRepository.activateWorkspace(workspace: workspace);
    if (!mounted) return;
    setState(() => _activeWorkspace = workspace);
  }

  Future<void> _onWorkspaceChanged(FinLapaSpreadsheet workspace) async {
    await _workspaceRepository.activateWorkspace(workspace: workspace);
    if (!mounted) return;
    setState(() => _activeWorkspace = workspace);
  }

  void _onActiveWorkspaceDeleted() {
    if (!mounted) return;
    setState(() => _activeWorkspace = null);
  }

  Future<FinLapaSpreadsheet> _createWorkspace(String name) {
    return _workspaceRepository.createWorkspace(
      user: widget.user,
      name: name,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isBootstrapping) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_activeWorkspace == null) {
      return OnboardingScreen(
        user: widget.user,
        onComplete: _completeWorkspaceSelection,
      );
    }

    return HomeScreen(
      key: ValueKey(_activeWorkspace!.id),
      user: widget.user,
      googleSignIn: widget.googleSignIn,
      activeWorkspace: _activeWorkspace!,
      onWorkspaceChanged: _onWorkspaceChanged,
      onActiveWorkspaceDeleted: _onActiveWorkspaceDeleted,
      onCreateWorkspace: _createWorkspace,
    );
  }
}
