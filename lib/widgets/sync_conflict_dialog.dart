// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/neo_sync_models.dart';
import 'dart:io';

/// Conflict resolution options
enum ConflictResolution {
  keepLocal, // Keep local version
  keepCloud, // Keep cloud version
  keepBoth, // Keep both (create copy)
}

/// Conflict resolution result
class ConflictResult {
  final ConflictResolution resolution;
  final bool applyToAll;

  ConflictResult({required this.resolution, this.applyToAll = false});
}

/// Steam-style dialog to resolve synchronization conflicts
class SyncConflictDialog extends StatefulWidget {
  final NeoSyncFile cloudFile;
  final File localFile;
  final String conflictMessage;

  const SyncConflictDialog({
    super.key,
    required this.cloudFile,
    required this.localFile,
    required this.conflictMessage,
  });

  @override
  State<SyncConflictDialog> createState() => _SyncConflictDialogState();
}

class _SyncConflictDialogState extends State<SyncConflictDialog> {
  ConflictResolution _selectedResolution = ConflictResolution.keepCloud;
  bool _applyToAll = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.warning, color: Colors.orange),
          const SizedBox(width: 8),
          Text(AppLocale.syncConflictDetected.getString(context)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.conflictMessage,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),

            // File information
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'File: ${widget.cloudFile.fileName}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),

                  // Local file information
                  _buildFileInfo(
                    AppLocale.localVersion.getString(context),
                    Icons.computer,
                    _getLocalFileInfo(),
                  ),

                  const SizedBox(height: 8),

                  // Cloud file information
                  _buildFileInfo(
                    AppLocale.cloudVersion.getString(context),
                    Icons.cloud,
                    _getCloudFileInfo(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Resolution options
            Text(
              AppLocale.chooseConflictRes.getString(context),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),

            // Option: Keep local
            RadioListTile<ConflictResolution>(
              title: Text(AppLocale.keepLocal.getString(context)),
              subtitle: Text(AppLocale.keepLocalDesc.getString(context)),
              value: ConflictResolution.keepLocal,
              groupValue: _selectedResolution,
              onChanged: (value) {
                setState(() {
                  _selectedResolution = value!;
                });
              },
            ),

            // Option: Keep cloud
            RadioListTile<ConflictResolution>(
              title: Text(AppLocale.keepCloud.getString(context)),
              subtitle: Text(AppLocale.keepCloudDesc.getString(context)),
              value: ConflictResolution.keepCloud,
              groupValue: _selectedResolution,
              onChanged: (value) {
                setState(() {
                  _selectedResolution = value!;
                });
              },
            ),

            // Option: Keep both
            RadioListTile<ConflictResolution>(
              title: Text(AppLocale.keepBoth.getString(context)),
              subtitle: Text(AppLocale.keepBothDesc.getString(context)),
              value: ConflictResolution.keepBoth,
              groupValue: _selectedResolution,
              onChanged: (value) {
                setState(() {
                  _selectedResolution = value!;
                });
              },
            ),

            const SizedBox(height: 8),

            // Checkbox to apply to all
            CheckboxListTile(
              title: Text(AppLocale.applyToAll.getString(context)),
              subtitle: Text(AppLocale.applyToAllDesc.getString(context)),
              value: _applyToAll,
              onChanged: (value) {
                setState(() {
                  _applyToAll = value ?? false;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocale.cancel.getString(context)),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(
              ConflictResult(
                resolution: _selectedResolution,
                applyToAll: _applyToAll,
              ),
            );
          },
          child: Text(AppLocale.apply.getString(context)),
        ),
      ],
    );
  }

  Widget _buildFileInfo(String title, IconData icon, Map<String, String> info) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 4),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...info.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(entry.key, style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    entry.value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, String> _getLocalFileInfo() {
    final stat = widget.localFile.statSync();
    return {
      'Size': _formatBytes(stat.size),
      'Modified': _formatDateTime(stat.modified),
    };
  }

  Map<String, String> _getCloudFileInfo() {
    return {
      'Size': _formatBytes(widget.cloudFile.fileSize),
      'Uploaded': _formatDateTime(widget.cloudFile.uploadedAt),
    };
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    return '${local.day}/${local.month}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
