import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../dlna/domain/models/dlna_device.dart';
import '../../dlna/data/dlna_manager.dart';
import '../data/player_manager.dart';
import 'speaker_selector_modal.dart';

class NowPlayingScreen extends StatefulWidget {
  final String title;
  final String artist;
  final String album;
  final String coverUrl;
  final String qualityBadge;
  final DlnaDevice activeDevice;
  final List<DlnaDevice> availableDevices;
  final Function(DlnaDevice)? onSelectDevice;

  NowPlayingScreen({
    super.key,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    this.qualityBadge = 'FLAC 16-bit 44.1kHz',
    DlnaDevice? activeDevice,
    DlnaDevice? selectedDevice,
    List<DlnaDevice>? availableDevices,
    this.onSelectDevice,
  })  : activeDevice = activeDevice ?? selectedDevice ?? DlnaDevice.localSpeaker,
        availableDevices = availableDevices ?? [DlnaDevice.localSpeaker];

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  final PlayerManager _playerManager = PlayerManager.instance;
  final DlnaManager _dlnaManager = DlnaManager.instance;
  bool _isUserDraggingSlider = false;
  double _dragSliderValue = 0.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DlnaDevice>(
      valueListenable: _dlnaManager.selectedDeviceNotifier,
      builder: (context, selectedDevice, child) {
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
                  selectedDevice.isLocalSpeaker ? Icons.phone_android : Icons.speaker_group,
                  color: AppColors.cyanAccent,
                ),
                onPressed: () {
                  SpeakerSelectorModal.show(
                    context,
                    devices: _dlnaManager.devices,
                    selectedDevice: selectedDevice,
                    onSelectDevice: (dev) => _dlnaManager.selectDevice(dev),
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
                // Large Cover Art
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: widget.coverUrl.isNotEmpty
                        ? Image.network(
                            widget.coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.music_note, size: 100, color: AppColors.cyanAccent),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.music_note, size: 100, color: AppColors.cyanAccent),
                          ),
                  ),
                ),
                const Spacer(),
                // Track Info & Quality Badge
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
                    ValueListenableBuilder<String>(
                      valueListenable: _playerManager.qualityBadgeNotifier,
                      builder: (context, badge, _) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.cyanAccent.withOpacity(0.5)),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.cyanAccent),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Real-time Progress Slider
                ValueListenableBuilder<int>(
                  valueListenable: _playerManager.durationSecondsNotifier,
                  builder: (context, durationSec, _) {
                    final maxDuration = durationSec > 0 ? durationSec.toDouble() : 210.0;
                    return ValueListenableBuilder<int>(
                      valueListenable: _playerManager.progressSecondsNotifier,
                      builder: (context, progressSec, _) {
                        final currentVal = _isUserDraggingSlider
                            ? _dragSliderValue
                            : progressSec.toDouble().clamp(0.0, maxDuration);

                        return Column(
                          children: [
                            Slider(
                              value: currentVal,
                              min: 0.0,
                              max: maxDuration,
                              activeColor: AppColors.cyanAccent,
                              inactiveColor: AppColors.surfaceLight,
                              onChangeStart: (val) {
                                setState(() {
                                  _isUserDraggingSlider = true;
                                  _dragSliderValue = val;
                                });
                              },
                              onChanged: (val) {
                                setState(() {
                                  _dragSliderValue = val;
                                });
                              },
                              onChangeEnd: (val) {
                                setState(() {
                                  _isUserDraggingSlider = false;
                                });
                                _playerManager.seekTo(val.toInt());
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_formatDuration(currentVal.toInt()), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  Text(_formatDuration(maxDuration.toInt()), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Playback Control Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.shuffle, color: Colors.white54),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 36, color: Colors.white),
                      onPressed: () {
                        _playerManager.seekTo(0);
                      },
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: _playerManager.isPlayingNotifier,
                      builder: (context, isPlaying, _) {
                        return IconButton(
                          icon: Icon(
                            isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                            size: 64,
                            color: AppColors.cyanAccent,
                          ),
                          onPressed: () {
                            _playerManager.togglePlayPause();
                          },
                        );
                      },
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
      },
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
