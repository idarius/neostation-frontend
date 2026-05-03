import 'package:flutter/material.dart';

/// Stub — full Hello-World debug UI added in Phase 1, final UI in Phase 2.
class SmbSyncContent extends StatelessWidget {
  final VoidCallback onBack;

  const SmbSyncContent({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onBack,
        child: const Text('SMB sync — Phase 0 placeholder'),
      ),
    );
  }
}
