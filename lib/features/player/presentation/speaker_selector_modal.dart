import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../dlna/domain/models/dlna_device.dart';

class SpeakerSelectorModal extends StatelessWidget {
  final List<DlnaDevice> devices;
  final DlnaDevice selectedDevice;
  final Function(DlnaDevice) onSelectDevice;

  const SpeakerSelectorModal({
    super.key,
    required this.devices,
    required this.selectedDevice,
    required this.onSelectDevice,
  });

  static void show(
    BuildContext context, {
    required List<DlnaDevice> devices,
    required DlnaDevice selectedDevice,
    required Function(DlnaDevice) onSelectDevice,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SpeakerSelectorModal(
        devices: devices,
        selectedDevice: selectedDevice,
        onSelectDevice: onSelectDevice,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                '오디오 출력 스피커 선택',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.cyanAccent,
                ),
              ),
            ),
            const Divider(color: Colors.white24),
            ...devices.map((device) {
              final isSelected = device.udn == selectedDevice.udn;
              return ListTile(
                leading: Icon(
                  device.isLocalSpeaker ? Icons.phone_android : Icons.speaker_group,
                  color: isSelected ? AppColors.cyanAccent : Colors.white70,
                ),
                title: Text(
                  device.friendlyName,
                  style: TextStyle(
                    color: isSelected ? AppColors.cyanAccent : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: device.isLocalSpeaker
                    ? const Text('스마트폰 직출력', style: TextStyle(color: AppColors.textSecondary))
                    : Text('DLNA Renderer (${device.locationUrl})',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: AppColors.cyanAccent)
                    : null,
                onTap: () {
                  onSelectDevice(device);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
