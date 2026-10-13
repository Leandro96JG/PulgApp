import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'qr_pairing.dart';

final class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

final class _QrScannerPageState extends State<QrScannerPage> {
  late final MobileScannerController _controller;
  bool _detected = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_detected) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null) {
        final pairingData = QrPairingParser.tryParse(raw);
        if (pairingData != null) {
          _detected = true;
          HapticFeedback.mediumImpact();
          Navigator.of(context).pop(pairingData);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam_off_rounded,
                    size: 56,
                    color: Colors.white54,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Camera could not be started: ${error.errorCode.name}',
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Return to manual pairing'),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Scanner reticle overlay
        IgnorePointer(
          child: Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        // Top controls bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Scan Pulgapp QR Code',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Colors.black87, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
                  tooltip: 'Toggle Flash',
                  onPressed: () => _controller.toggleTorch(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Bottom helper hint
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: SafeArea(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Point at the QR code on your PC screen',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
