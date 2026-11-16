import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../dlna/domain/models/dlna_device.dart';
import '../../dlna/data/dlna_manager.dart';
import '../../tidal_api/domain/models/media_item.dart';
import '../data/player_manager.dart';
import 'speaker_selector_modal.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
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
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  PlayerManager get _playerManager => ref.read(playerManagerProvider);
  DlnaManager get _dlnaManager => ref.read(dlnaManagerProvider);
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
              // 재생 대기열 (Queue List) 버튼
              IconButton(
                icon: const Icon(Icons.queue_music, color: Colors.white70),
                tooltip: '재생 대기열',
                onPressed: () => _showQueueBottomSheet(context),
              ),
              // 스피커/출력 기기 선택 버튼
              IconButton(
                icon: Icon(
                  selectedDevice.isLocalSpeaker ? Icons.phone_android : Icons.speaker_group,
                  color: AppColors.cyanAccent,
                ),
                tooltip: '출력 기기 선택',
                onPressed: () {
                  SpeakerSelectorModal.show(
                    context,
                    devices: _dlnaManager.devices,
                    selectedDevice: selectedDevice,
                    onSelectDevice: (dev) => _playerManager.switchPlaybackDevice(dev),
                  );
                },
              ),
            ],
          ),
          body: ValueListenableBuilder<MediaTrack?>(
            valueListenable: _playerManager.currentTrackNotifier,
            builder: (context, track, _) {
              final currentTitle = track?.title ?? widget.title;
              final currentArtist = track?.artistName ?? widget.artist;
              final currentAlbum = track?.albumTitle ?? widget.album;
              final currentCoverUrl = track?.coverUrl ?? widget.coverUrl;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
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
                        child: currentCoverUrl.isNotEmpty
                            ? Image.network(
                                currentCoverUrl,
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
                    // Track Info & Dynamic Quality Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentTitle,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$currentArtist • $currentAlbum',
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
                            final isMax = badge.contains('MAX') || badge.contains('24-bit');
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isMax ? Colors.amber.withOpacity(0.15) : AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isMax ? Colors.amberAccent : AppColors.cyanAccent.withOpacity(0.5),
                                ),
                              ),
                              child: Text(
                                badge,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isMax ? Colors.amberAccent : AppColors.cyanAccent,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
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

                            final canSeek = _playerManager.canSeekNotifier.value;
                            return Column(
                              children: [
                                Slider(
                                  value: currentVal,
                                  min: 0.0,
                                  max: maxDuration,
                                  activeColor: AppColors.cyanAccent,
                                  inactiveColor: AppColors.surfaceLight,
                                  // DASH(Hi-Res) 스피커 재생처럼 탐색이 안 되는 경우 슬라이더를 비활성화한다.
                                  onChangeStart: !canSeek ? null : (val) {
                                    setState(() {
                                      _isUserDraggingSlider = true;
                                      _dragSliderValue = val;
                                    });
                                  },
                                  onChanged: !canSeek ? null : (val) {
                                    setState(() {
                                      _dragSliderValue = val;
                                    });
                                  },
                                  onChangeEnd: !canSeek ? null : (val) {
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
                    const SizedBox(height: 12),
                    // Playback Control Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Shuffle Button
                        ValueListenableBuilder<bool>(
                          valueListenable: _playerManager.isShuffleNotifier,
                          builder: (context, isShuffle, _) {
                            return IconButton(
                              icon: Icon(
                                Icons.shuffle,
                                color: isShuffle ? AppColors.cyanAccent : Colors.white54,
                              ),
                              onPressed: () {
                                _playerManager.toggleShuffle();
                              },
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_previous, size: 36, color: Colors.white),
                          onPressed: () {
                            _playerManager.skipToPrevious();
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
                          onPressed: () {
                            _playerManager.skipToNext();
                          },
                        ),
                        // Repeat Button
                        ValueListenableBuilder<PlaybackRepeatMode>(
                          valueListenable: _playerManager.repeatModeNotifier,
                          builder: (context, repeatMode, _) {
                            IconData iconData = Icons.repeat;
                            Color iconColor = Colors.white54;
                            if (repeatMode == PlaybackRepeatMode.all) {
                              iconData = Icons.repeat;
                              iconColor = AppColors.cyanAccent;
                            } else if (repeatMode == PlaybackRepeatMode.one) {
                              iconData = Icons.repeat_one;
                              iconColor = AppColors.cyanAccent;
                            }
                            return IconButton(
                              icon: Icon(iconData, color: iconColor),
                              onPressed: () {
                                _playerManager.toggleRepeat();
                              },
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Volume Control Slider (통합 볼륨 조절)
                    ValueListenableBuilder<int>(
                      valueListenable: _playerManager.volumeNotifier,
                      builder: (context, volume, _) {
                        return Row(
                          children: [
                            const Icon(Icons.volume_down, size: 20, color: Colors.white54),
                            Expanded(
                              child: Slider(
                                value: volume.toDouble(),
                                min: 0.0,
                                max: 100.0,
                                activeColor: AppColors.cyanAccent,
                                inactiveColor: AppColors.surfaceLight,
                                onChanged: (val) {
                                  _playerManager.setVolume(val.round(), isFinal: false);
                                },
                                onChangeEnd: (val) {
                                  _playerManager.setVolume(val.round());
                                },
                              ),
                            ),
                            const Icon(Icons.volume_up, size: 20, color: Colors.white54),
                          ],
                        );
                      },
                    ),
                    const Spacer(),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// TIDAL 공식 앱 스타일의 재생 대기열 (Queue List) Bottom Sheet
  void _showQueueBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '재생 대기열 (Queue)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      ValueListenableBuilder<List<MediaTrack>>(
                        valueListenable: _playerManager.queueNotifier,
                        builder: (_, q, __) => Text(
                          '총 ${q.length}곡',
                          style: const TextStyle(fontSize: 13, color: AppColors.cyanAccent),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                Expanded(
                  child: ValueListenableBuilder<List<MediaTrack>>(
                    valueListenable: _playerManager.queueNotifier,
                    builder: (context, queue, _) {
                      if (queue.isEmpty) {
                        return const Center(
                          child: Text('대기열이 비어 있습니다.', style: TextStyle(color: AppColors.textSecondary)),
                        );
                      }

                      return ValueListenableBuilder<int>(
                        valueListenable: _playerManager.queueIndexNotifier,
                        builder: (context, currentIndex, _) {
                          return ListView.builder(
                            controller: scrollController,
                            itemCount: queue.length,
                            itemBuilder: (context, index) {
                              final track = queue[index];
                              final isPlayingThis = index == currentIndex;

                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isPlayingThis ? AppColors.surfaceLight.withOpacity(0.6) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: isPlayingThis
                                      ? Border.all(color: AppColors.cyanAccent.withOpacity(0.8), width: 1.2)
                                      : null,
                                ),
                                child: ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: track.coverUrl.isNotEmpty
                                        ? Image.network(
                                            track.coverUrl,
                                            width: 44,
                                            height: 44,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              width: 44,
                                              height: 44,
                                              color: AppColors.surfaceLight,
                                              child: const Icon(Icons.music_note, color: Colors.white54, size: 20),
                                            ),
                                          )
                                        : Container(
                                            width: 44,
                                            height: 44,
                                            color: AppColors.surfaceLight,
                                            child: const Icon(Icons.music_note, color: Colors.white54, size: 20),
                                          ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          track.title,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: isPlayingThis ? FontWeight.bold : FontWeight.normal,
                                            color: isPlayingThis ? AppColors.cyanAccent : Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      // 음질 뱃지
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: track.isMax ? Colors.amber.withOpacity(0.2) : AppColors.surfaceLight,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          track.qualityBadgeText,
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: track.isMax ? Colors.amberAccent : AppColors.cyanAccent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    track.artistName,
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: isPlayingThis
                                      ? const Icon(Icons.equalizer, color: AppColors.cyanAccent, size: 22)
                                      : Text(
                                          _formatDuration(track.durationSeconds),
                                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                        ),
                                  onTap: () {
                                    _playerManager.playQueueIndex(index);
                                    Navigator.pop(ctx);
                                  },
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
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
