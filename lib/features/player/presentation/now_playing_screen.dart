import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../dlna/domain/models/dlna_device.dart';
import 'speaker_selector_modal.dart';

class NowPlayingScreen extends StatefulWidget {
  final String title;
  final String artist;
  final String album;
  final String coverUrl;
  final String qualityBadge;
  final DlnaDevice activeDevice;
  final List<DlnaDevice> availableDevices;
  final Function(DlnaDevice) onSelectDevice;

  const NowPlayingScreen({
    super.key,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    this.qualityBadge = 'FLAC 16-bit 44.1kHz',
    required this.activeDevice,
    required this.availableDevices,
    required this.onSelectDevice,
  });

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool _isPlaying = true;
  double _sliderValue = 45.0;
  final double _maxDuration = 210.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, size: 32, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('지금 재생 중', style: TextStyle(fontSize: 16, color: Colors.white70)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              widget.activeDevice.isLocalSpeaker ? Icons.phone_android : Icons.speaker_group,
              color: AppColors.cyanAccent,
            ),
            onPressed: () {
              SpeakerSelectorModal.show(
                context,
                devices: widget.availableDevices,
                selectedDevice: widget.activeDevice,
                onSelectDevice: widget.onSelectDevice,
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          children: [
            const Spacer(),
            Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.music_note, size: 100, color: AppColors.cyanAccent),
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.artist} • ${widget.album}',
                        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.cyanAccent.withOpacity(0.5)),
                  ),
                  child: Text(
                    widget.qualityBadge,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.cyanAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Slider(
              value: _sliderValue,
              min: 0.0,
              max: _maxDuration,
              activeColor: AppColors.cyanAccent,
              inactiveColor: AppColors.surfaceLight,
              onChanged: (val) => setState(() => _sliderValue = val),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(_sliderValue.toInt()), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Text(_formatDuration(_maxDuration.toInt()), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.shuffle, color: Colors.white54),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous, size: 36, color: Colors.white),
                  onPressed: () {},
                ),
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    size: 64,
                    color: AppColors.cyanAccent,
                  ),
                  onPressed: () => setState(() => _isPlaying = !_isPlaying),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, size: 36, color: Colors.white),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.repeat, color: Colors.white54),
                  onPressed: () {},
                ),
              ],
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
