import 'package:flutter/material.dart';

/// Placeholder — full implementation in next commit.
class LocalSyncContent extends StatelessWidget {
  final VoidCallback onBack;

  const LocalSyncContent({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onBack,
        child: const Text('Local / NAS — placeholder'),
      ),
    );
  }
}
