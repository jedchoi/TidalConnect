import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../dlna/domain/models/dlna_device.dart';
import 'now_playing_screen.dart';

class MiniPlayerWidget extends StatefulWidget {
  final String title;
  final String artist;
  final String album;
  final String coverUrl;

  const MiniPlayerWidget({
    super.key,
    this.title = 'Tidal 음원 선택 안됨',
    this.artist = 'Tidal Connect Lite',
    this.album = 'Tidal Collection',
    this.coverUrl = '',
  });

  @override
  State<MiniPlayerWidget> createState() => _MiniPlayerWidgetState();
}

class _MiniPlayerWidgetState extends State<MiniPlayerWidget> {
  bool _isPlaying = false;
  DlnaDevice _selectedDevice = DlnaDevice.localSpeaker;
  final List<DlnaDevice> _devices = [
    DlnaDevice.localSpeaker,
    DlnaDevice(
      udn: 'chord_poly_123',
      friendlyName: 'Chord Poly (DLNA)',
      locationUrl: 'http://192.168.1.100:49152/description.xml',
      avTransportControlUrl: 'http://192.168.1.100:49152/upnp/control/AVTransport',
      renderingControlUrl: 'http://192.168.1.100:49152/upnp/control/RenderingControl',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NowPlayingScreen(
              title: widget.title,
              artist: widget.artist,
              album: widget.album,
              coverUrl: widget.coverUrl,
              activeDevice: _selectedDevice,
              availableDevices: _devices,
              onSelectDevice: (dev) => setState(() => _selectedDevice = dev),
            ),
          ),
        );
      },
      child: Container(
        height: 64,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.music_note, color: AppColors.cyanAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.artist,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: AppColors.cyanAccent,
                  size: 28,
                ),
                onPressed: () {
                  setState(() => _isPlaying = !_isPlaying);
                },
              ),
              IconButton(
                icon: Icon(
                  _selectedDevice.isLocalSpeaker ? Icons.phone_android : Icons.speaker_group,
                  color: AppColors.cyanAccent,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NowPlayingScreen(
                        title: widget.title,
                        artist: widget.artist,
                        album: widget.album,
                        coverUrl: widget.coverUrl,
                        activeDevice: _selectedDevice,
                        availableDevices: _devices,
                        onSelectDevice: (dev) => setState(() => _selectedDevice = dev),
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
