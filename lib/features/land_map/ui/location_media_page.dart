import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../auth/providers/auth_provider.dart';
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
        _errorMessage =
            'Sign in with a verified account to see uploaded media.';
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
                Padding(
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
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LocationMediaViewerPage(item: item),
                        ),
                      ),
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

        backgroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
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
                                    height: _videoController!.value.size.height,
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
            const SizedBox(height: 16),
            Text(
              placeText == '—' ? 'Saved location' : placeText,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              coordinateText == '—'
                  ? 'Coordinates unavailable'
                  : coordinateText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            _detailRow('Place', placeText),
            _detailRow('Address', addressText),
            _detailRow('Coordinates', coordinateText),
            _detailRow('UTM', utmText),
            _detailRow('Reference ellipsoid', referenceEllipsoid.displayName),
            _detailRow('Coordinate format', coordinateFormat.displayName),
            _detailRow('Media type', item.type.isEmpty ? 'media' : item.type),
            _detailRow('MIME', item.mimeType.isEmpty ? '—' : item.mimeType),
            _detailRow('Size', _fileSizeLabel(item.fileSize)),
            _detailRow(
              'File name',
              item.fileName.isEmpty ? '—' : item.fileName,
            ),
            _detailRow('Path', item.filePath.isEmpty ? '—' : item.filePath),
            _detailRow(
              'Location ID',
              item.locationId.isEmpty ? '—' : item.locationId,
            ),
            if (item.createdAt != null)
              _detailRow('Created', _formatCloudDate(item.createdAt!)),
            if (item.updatedAt != null)
              _detailRow('Updated', _formatCloudDate(item.updatedAt!)),
            const SizedBox(height: 12),
            if (item.isVideo && _videoController != null)
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
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(child: Text(value)),
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
