import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../dlna/domain/models/dlna_device.dart';
import '../../dlna/data/dlna_manager.dart';
import '../../tidal_api/domain/models/media_item.dart';
import '../data/player_manager.dart';
import 'now_playing_screen.dart';

class MiniPlayerWidget extends StatefulWidget {
  final bool autoStartDiscovery;

  const MiniPlayerWidget({
    super.key,
    this.autoStartDiscovery = true,
  });

  @override
  State<MiniPlayerWidget> createState() => _MiniPlayerWidgetState();
}

class _MiniPlayerWidgetState extends State<MiniPlayerWidget> {
  final DlnaManager _dlnaManager = DlnaManager.instance;
  final PlayerManager _playerManager = PlayerManager.instance;

  @override
  void initState() {
    super.initState();
    if (widget.autoStartDiscovery) {
      _dlnaManager.discoverDevices();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MediaTrack?>(
      valueListenable: _playerManager.currentTrackNotifier,
      builder: (context, currentTrack, _) {
        final title = currentTrack?.title ?? 'Tidal 음원 선택 안됨';
        final artist = currentTrack?.artistName ?? 'Tidal Connect Lite';
        final album = currentTrack?.albumTitle ?? 'Tidal Collection';
        final coverUrl = currentTrack?.coverUrl ?? '';

        return ValueListenableBuilder<DlnaDevice>(
          valueListenable: _dlnaManager.selectedDeviceNotifier,
          builder: (context, selectedDevice, child) {
            return ValueListenableBuilder<bool>(
              valueListenable: _playerManager.isPlayingNotifier,
              builder: (context, isPlaying, _) {
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NowPlayingScreen(
                          title: title,
                          artist: artist,
                          album: album,
                          coverUrl: coverUrl,
                          selectedDevice: selectedDevice,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cyanAccent.withOpacity(0.3)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: coverUrl.isNotEmpty
                              ? Image.network(
                                  coverUrl,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 48,
                                    height: 48,
                                    color: AppColors.cardHover,
                                    child: const Icon(Icons.music_note, color: AppColors.cyanAccent),
                                  ),
                                )
                              : Container(
                                  width: 48,
                                  height: 48,
                                  color: AppColors.cardHover,
                                  child: const Icon(Icons.music_note, color: AppColors.cyanAccent),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    selectedDevice.isLocalSpeaker ? Icons.phone_android : Icons.speaker,
                                    size: 12,
                                    color: AppColors.cyanAccent,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '$artist • ${selectedDevice.friendlyName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            selectedDevice.isLocalSpeaker ? Icons.phone_android : Icons.speaker_group,
                            color: AppColors.cyanAccent,
                          ),
                          tooltip: '출력 기기 변경',
                          onPressed: () => _showSpeakerSelectorModal(context),
                        ),
                        IconButton(
                          icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 36),
                          color: AppColors.cyanAccent,
                          onPressed: () {
                            _playerManager.togglePlayPause();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showSpeakerSelectorModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return ValueListenableBuilder<List<DlnaDevice>>(
          valueListenable: _dlnaManager.devicesNotifier,
          builder: (context, devices, child) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '오디오 재생 출력 기기 선택',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: AppColors.cyanAccent),
                        onPressed: () => _dlnaManager.discoverDevices(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        final isSelected = device.udn == _dlnaManager.selectedDevice.udn;
                        return ListTile(
                          leading: Icon(
                            device.isLocalSpeaker ? Icons.phone_android : Icons.speaker,
                            color: isSelected ? AppColors.cyanAccent : Colors.white70,
                          ),
                          title: Text(
                            device.friendlyName,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            device.isLocalSpeaker ? '스마트폰 내장 스피커' : device.locationUrl,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle, color: AppColors.cyanAccent)
                              : null,
                          onTap: () {
                            _dlnaManager.selectDevice(device);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
