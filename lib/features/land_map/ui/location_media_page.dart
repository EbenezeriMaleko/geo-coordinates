import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../../auth/providers/auth_provider.dart';
import '../../auth/ui/login_page.dart';
import '../models/coordinate_format.dart';
import '../models/location_media_models.dart';
import '../models/reference_ellipsoid.dart';
import '../services/location_media_service.dart';
import '../services/utm_converter.dart';
import '../state/settings_provider.dart';

class LocationMediaPage extends ConsumerStatefulWidget {
  final String? initialType;

  const LocationMediaPage({super.key, this.initialType});

  @override
  ConsumerState<LocationMediaPage> createState() => _LocationMediaPageState();
}

class _LocationMediaPageState extends ConsumerState<LocationMediaPage> {
  final LocationMediaService _service = LocationMediaService();
  final List<LocationMediaItem> _items = <LocationMediaItem>[];
  bool _isLoading = true;
  String? _errorMessage;
  String? _filterType;
  bool _showDeleteToast = false;

  @override
  void initState() {
    super.initState();
    _filterType = widget.initialType;
    Future.microtask(_loadMedia);
  }

  Future<void> _loadMedia() async {
    final session = ref.read(authSessionProvider);
    if (!session.isLoggedIn || !session.isVerified) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'not_logged_in';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _service.listMedia(
        session.token,
        type: _filterType,
        perPage: 50,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _isLoading = false;
        if (_showDeleteToast) {
          _showDeleteToast = false;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Media deleted.')));
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  void _setFilter(String? filter) {
    if (_filterType == filter) return;
    setState(() => _filterType = filter);
    _loadMedia();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Location media',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),

        backgroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadMedia,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedRefresh,
              size: 20,
              color: Colors.black87,
            ),
          ),
        ],
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedArrowLeft01,
            color: Colors.black87,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadMedia,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _filterType == null,
                    onSelected: (_) => _setFilter(null),
                  ),
                  ChoiceChip(
                    label: const Text('Images'),
                    selected: _filterType == 'image',
                    onSelected: (_) => _setFilter('image'),
                  ),
                  ChoiceChip(
                    label: const Text('Videos'),
                    selected: _filterType == 'video',
                    onSelected: (_) => _setFilter('video'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 64),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                _errorMessage == 'not_logged_in'
                    ? Padding(
                        padding: const EdgeInsets.only(top: 48),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off_rounded,
                              size: 52,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Sign in to view uploaded media',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your cloud media will appear here once you sign in with a verified account.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.black54,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final result = await Navigator.of(context)
                                    .push<bool>(
                                      MaterialPageRoute<bool>(
                                        builder: (_) => const LoginPage(
                                          returnToPreviousPage: true,
                                        ),
                                      ),
                                    );
                                if (result == true && mounted) {
                                  _loadMedia();
                                }
                              },
                              icon: const Icon(Icons.login_rounded, size: 18),
                              label: const Text('Sign In'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF001F3F),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(top: 48),
                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.black54,
                          ),
                        ),
                      )
              else if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Text(
                    'No uploaded media found yet.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return _MediaCard(
                      item: item,
                      onTap: () async {
                        final deleted = await Navigator.of(context).push<bool>(
                          MaterialPageRoute<bool>(
                            builder: (_) => LocationMediaViewerPage(item: item),
                          ),
                        );
                        if (deleted == true && mounted) {
                          _showDeleteToast = true;
                          await _loadMedia();
                        }
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final LocationMediaItem item;
  final VoidCallback onTap;

  const _MediaCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.isVideo
                        ? Container(
                            color: Colors.black87,
                            child: const Center(
                              child: Icon(
                                Icons.play_circle_fill,
                                color: Colors.white,
                                size: 52,
                              ),
                            ),
                          )
                        : Image.network(
                            item.resolvedUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  color: Colors.black12,
                                  child: const Center(
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                          ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: _TypeBadge(
                        label: item.type.isEmpty ? 'media' : item.type,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.location?.name ?? 'Unnamed location',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _fileSizeLabel(item.fileSize),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String label;

  const _TypeBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class LocationMediaViewerPage extends ConsumerStatefulWidget {
  final LocationMediaItem item;

  const LocationMediaViewerPage({super.key, required this.item});

  @override
  ConsumerState<LocationMediaViewerPage> createState() =>
      _LocationMediaViewerPageState();
}

class _LocationMediaViewerPageState
    extends ConsumerState<LocationMediaViewerPage> {
  VideoPlayerController? _videoController;
  bool _loadingVideo = false;
  bool _deletingMedia = false;
  final LocationMediaService _service = LocationMediaService();

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideo() async {
    if (!widget.item.isVideo) return;
    setState(() => _loadingVideo = true);
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.item.resolvedUrl),
    );
    await controller.initialize();
    await controller.setLooping(true);
    await controller.play();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _videoController = controller;
      _loadingVideo = false;
    });
  }

  Future<void> _deleteMedia() async {
    if (_deletingMedia) return;
    final session = ref.read(authSessionProvider);
    if (!session.isLoggedIn || !session.isVerified) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign in to delete media.')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete media?'),
        content: const Text(
          'This will permanently delete the media from the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    setState(() => _deletingMedia = true);

    try {
      await _service.deleteMedia(session.token, widget.item.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _deletingMedia = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _shareMedia() async {
    final item = widget.item;
    try {
      // Download file to temp dir then share
      final response = await http.get(Uri.parse(item.resolvedUrl));
      if (response.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to download media for sharing.'),
          ),
        );
        return;
      }
      final tempDir = await getTemporaryDirectory();
      final ext = item.isVideo ? '.mp4' : '.jpg';
      final tempFile = File('${tempDir.path}/share_${item.id}$ext');
      await tempFile.writeAsBytes(response.bodyBytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path)],
          text: item.location?.name ?? item.fileName,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to share media.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final coordinateFormat = ref.watch(coordinateFormatProvider);
    final referenceEllipsoid = ref.watch(referenceEllipsoidProvider);
    final placeText = _cloudPlaceText(item);
    final addressText = _cloudAddressText(item);
    final coordinateText = _cloudCoordinateText(item, coordinateFormat);
    final utmText = _cloudUtmText(item, referenceEllipsoid);
    final titleText = placeText == '—' ? 'Saved location' : placeText;
    final subtitleText = coordinateText == '—'
        ? 'Coordinates unavailable'
        : coordinateText;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          item.fileName,
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),

        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedArrowLeft01,
            color: Colors.black87,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _shareMedia,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedShare01,
              color: Colors.black87,
              size: 20,
            ),
          ),
          IconButton(
            onPressed: _deletingMedia ? null : _deleteMedia,
            icon: _deletingMedia
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : HugeIcon(
                    icon: HugeIcons.strokeRoundedDelete02,
                    color: Colors.red.shade600,
                    size: 20,
                  ),
          ),
        ],
        backgroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.46,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Colors.black),
                      item.isVideo
                          ? _loadingVideo || _videoController == null
                                ? const ColoredBox(
                                    color: Colors.black,
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : FittedBox(
                                    fit: BoxFit.contain,
                                    child: SizedBox(
                                      width: _videoController!.value.size.width,
                                      height:
                                          _videoController!.value.size.height,
                                      child: VideoPlayer(_videoController!),
                                    ),
                                  )
                          : Image.network(
                              item.resolvedUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: Colors.black12,
                                    child: const Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        size: 42,
                                      ),
                                    ),
                                  ),
                            ),
                      if (item.isVideo && _videoController != null)
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 16,
                          child: VideoProgressIndicator(
                            _videoController!,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: Colors.white,
                              bufferedColor: Colors.white38,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              titleText,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitleText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MediaMetaChip(
                  label: item.type.isEmpty ? 'Media' : item.type,
                  icon: item.isVideo ? Icons.videocam : Icons.photo,
                ),
                _MediaMetaChip(
                  label: _fileSizeLabel(item.fileSize),
                  icon: Icons.sd_storage,
                ),
                _MediaMetaChip(
                  label: item.mimeType.isEmpty ? 'MIME —' : item.mimeType,
                  icon: Icons.description,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _MediaSection(
              title: 'Location',
              children: [
                _detailRow('Place', placeText),
                _detailRow('Address', addressText),
              ],
            ),
            const SizedBox(height: 12),
            _MediaSection(
              title: 'Coordinates',
              children: [
                _detailRow('Lat/Lon', coordinateText),
                _detailRow('UTM', utmText),
                _detailRow('Ellipsoid', referenceEllipsoid.displayName),
                _detailRow('Format', coordinateFormat.displayName),
              ],
            ),
            const SizedBox(height: 12),
            _MediaSection(
              title: 'File',
              children: [
                _detailRow(
                  'File name',
                  item.fileName.isEmpty ? '—' : item.fileName,
                ),
                _detailRow('Path', item.filePath.isEmpty ? '—' : item.filePath),
                _detailRow('MIME', item.mimeType.isEmpty ? '—' : item.mimeType),
                _detailRow('Size', _fileSizeLabel(item.fileSize)),
              ],
            ),
            const SizedBox(height: 12),
            _MediaSection(
              title: 'System',
              children: [
                _detailRow(
                  'Location ID',
                  item.locationId.isEmpty ? '—' : item.locationId,
                ),
                if (item.createdAt != null)
                  _detailRow('Created', _formatCloudDate(item.createdAt!)),
                if (item.updatedAt != null)
                  _detailRow('Updated', _formatCloudDate(item.updatedAt!)),
              ],
            ),
            if (item.isVideo && _videoController != null) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  final controller = _videoController!;
                  setState(() {
                    controller.value.isPlaying
                        ? controller.pause()
                        : controller.play();
                  });
                },
                icon: Icon(
                  _videoController!.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
                label: Text(
                  _videoController!.value.isPlaying ? 'Pause' : 'Play',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _MediaSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black54,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _MediaMetaChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _MediaMetaChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _cloudPlaceText(LocationMediaItem item) {
  final location = item.location;
  final value = [location?.place, location?.name]
      .whereType<String>()
      .map((value) => value.trim())
      .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  return value.isEmpty ? '—' : value;
}

String _cloudAddressText(LocationMediaItem item) {
  final location = item.location;
  final value = [location?.address, location?.description]
      .whereType<String>()
      .map((value) => value.trim())
      .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  return value.isEmpty ? '—' : value;
}

String _cloudCoordinateText(
  LocationMediaItem item,
  CoordinateFormat coordinateFormat,
) {
  final latitude = item.location?.latitude;
  final longitude = item.location?.longitude;
  if (latitude == null || longitude == null) return '—';
  return CoordinateFormatter.format(latitude, longitude, coordinateFormat);
}

String _cloudUtmText(
  LocationMediaItem item,
  ReferenceEllipsoid referenceEllipsoid,
) {
  final latitude = item.location?.latitude;
  final longitude = item.location?.longitude;
  if (latitude == null || longitude == null) return '—';
  final utm = UtmConverter.fromLatLng(latitude, longitude, referenceEllipsoid);
  return utm?.toDisplayString() ?? 'UTM unavailable for this latitude';
}

String _formatCloudDate(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  final local = parsed.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/$year $hour:$minute';
}

String _fileSizeLabel(int bytes) {
  if (bytes <= 0) return '—';
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}
