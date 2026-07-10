import 'package:flutter/material.dart';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_storage_manager.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/domain/models/media_storage.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// One conversation scope the storage section can measure/clear.
class MediaStorageScopeOption {
  const MediaStorageScopeOption({required this.scope, required this.label});

  final MediaLibraryScope scope;
  final String label;
}

/// 229: user-invoked storage totals + per-type Clear actions for the "Media
/// & storage" sheet. Nothing is measured until the user asks for a scope —
/// no startup or per-build filesystem scans.
class MediaStorageUsageSection extends StatefulWidget {
  const MediaStorageUsageSection({
    super.key,
    required this.manager,
    required this.loadScopes,
  });

  final MediaStorageManager manager;
  final Future<List<MediaStorageScopeOption>> Function() loadScopes;

  @override
  State<MediaStorageUsageSection> createState() =>
      _MediaStorageUsageSectionState();
}

class _MediaStorageUsageSectionState extends State<MediaStorageUsageSection> {
  List<MediaStorageScopeOption> _scopes = const [];
  final Map<String, MediaStorageInventory> _inventories = {};
  final Set<String> _loading = {};

  @override
  void initState() {
    super.initState();
    widget.loadScopes().then((scopes) {
      if (mounted) setState(() => _scopes = scopes);
    }).catchError((_) {});
  }

  String _scopeKey(MediaLibraryScope scope) =>
      '${scope.lane.dbValue}/${scope.id}';

  Future<void> _measure(MediaStorageScopeOption option) async {
    final key = _scopeKey(option.scope);
    if (!_loading.add(key)) return;
    setState(() {});
    try {
      final inventory = await widget.manager.inventory(scope: option.scope);
      if (mounted) setState(() => _inventories[key] = inventory);
    } catch (_) {
      // Leave the row unmeasured; the user can retry.
    } finally {
      _loading.remove(key);
      if (mounted) setState(() {});
    }
  }

  Future<void> _clearType(
    MediaStorageScopeOption option,
    MediaStorageKind kind,
  ) async {
    await widget.manager.clearLocalCopiesForType(
      scope: option.scope,
      kind: kind,
    );
    await _measure(option);
  }

  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readableColors = context.backgroundReadableColors;

    String typeLabel(MediaStorageKind kind) => switch (kind) {
          MediaStorageKind.image => l10n.settings_media_type_image,
          MediaStorageKind.video => l10n.settings_media_type_video,
          MediaStorageKind.audio => l10n.settings_media_type_audio,
          _ => l10n.settings_media_type_file,
        };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            l10n.settings_media_storage_usage,
            style: TextStyle(
              color: readableColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final option in _scopes) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: readableColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_loading.contains(_scopeKey(option.scope)))
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (!_inventories.containsKey(_scopeKey(option.scope)))
                  TextButton(
                    key: ValueKey(
                      'media-storage-measure-${_scopeKey(option.scope)}',
                    ),
                    onPressed: () => _measure(option),
                    child: Text(
                      l10n.settings_media_storage_compute,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            if (_inventories[_scopeKey(option.scope)] case final inventory?)
              if (inventory.totalCount == 0)
                Text(
                  l10n.settings_media_storage_empty,
                  style: TextStyle(
                    color: readableColors.textMuted,
                    fontSize: 12,
                  ),
                )
              else
                for (final kind in const [
                  MediaStorageKind.image,
                  MediaStorageKind.video,
                  MediaStorageKind.audio,
                  MediaStorageKind.file,
                ])
                  if (inventory.totalFor(kind.mediaTypes.single).count > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${typeLabel(kind)} · '
                              '${inventory.totalFor(kind.mediaTypes.single).count} · '
                              '${formatBytes(inventory.totalFor(kind.mediaTypes.single).bytes)}',
                              style: TextStyle(
                                color: readableColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          TextButton(
                            key: ValueKey(
                              'media-storage-clear-${_scopeKey(option.scope)}-${kind.name}',
                            ),
                            onPressed: () => _clearType(option, kind),
                            child: Text(
                              l10n.settings_media_storage_clear_type,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
          ],
        ],
      ),
    );
  }
}
