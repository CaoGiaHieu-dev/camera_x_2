import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/src/mobile_scanner_controller.dart';
import 'package:mobile_scanner/src/mobile_scanner_exception.dart';
import 'package:mobile_scanner/src/objects/barcode_capture.dart';
import 'package:mobile_scanner/src/objects/mobile_scanner_arguments.dart';

typedef MobileScannerErrorBuilder = Widget Function(
  BuildContext,
  MobileScannerException,
  Widget?,
);

class MobileScanner extends StatefulWidget {
  final MobileScannerController? controller;

  final MobileScannerErrorBuilder? errorBuilder;

  final BoxFit fit;

  final void Function(BarcodeCapture barcodes) onDetect;

  final void Function(MobileScannerArguments? arguments)? onScannerStarted;

  final Widget Function(BuildContext, Widget?)? placeholderBuilder;

  final Rect? scanWindow;

  final bool startDelay;

  final Widget? overlay;

  const MobileScanner({
    this.controller,
    this.errorBuilder,
    this.fit = BoxFit.cover,
    required this.onDetect,
    this.onScannerStarted,
    this.placeholderBuilder,
    this.scanWindow,
    this.startDelay = false,
    this.overlay,
    super.key,
  });

  @override
  State<MobileScanner> createState() => _MobileScannerState();
}

class _MobileScannerState extends State<MobileScanner>
    with WidgetsBindingObserver {
  StreamSubscription<BarcodeCapture>? _barcodesSubscription;
  StreamSubscription<BarcodeCapture>? _imageSubscription;

  late MobileScannerController _controller;

  bool _resumeFromBackground = false;

  MobileScannerException? _startException;

  Widget _buildPlaceholderOrError(BuildContext context, Widget? child) {
    final error = _startException;

    if (error != null) {
      return widget.errorBuilder?.call(context, error, child) ??
          const ColoredBox(
            color: Colors.black,
            child: Center(child: Icon(Icons.error, color: Colors.white)),
          );
    }

    return widget.placeholderBuilder?.call(context, child) ??
        const ColoredBox(color: Colors.black);
  }

  Future<void> _startScanner() async {
    if (widget.startDelay) {
      await Future.delayed(const Duration(seconds: 1, milliseconds: 500));
    }

    _barcodesSubscription ??= _controller.barcodes.listen(
      widget.onDetect,
    );

    if (!_controller.autoStart) {
      debugPrint(
        'mobile_scanner: not starting automatically because autoStart is set to false in the controller.',
      );
      return;
    }

    _controller.start().then((arguments) {
      widget.onScannerStarted?.call(arguments);
    }).catchError((error) {
      if (mounted) {
        setState(() {
          _startException = error as MobileScannerException;
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.controller ?? MobileScannerController();
    _startScanner();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller.isStarting) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        _resumeFromBackground = false;
        _startScanner();
        break;
      case AppLifecycleState.paused:
        _resumeFromBackground = true;
        break;
      case AppLifecycleState.inactive:
        if (!_resumeFromBackground) {
          _controller.stop();
        }
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  Rect calculateScanWindowRelativeToTextureInPercentage(
    BoxFit fit,
    Rect scanWindow,
    Size textureSize,
    Size widgetSize,
  ) {
    double fittedTextureWidth;
    double fittedTextureHeight;

    switch (fit) {
      case BoxFit.contain:
        final widthRatio = widgetSize.width / textureSize.width;
        final heightRatio = widgetSize.height / textureSize.height;
        final scale = widthRatio < heightRatio ? widthRatio : heightRatio;
        fittedTextureWidth = textureSize.width * scale;
        fittedTextureHeight = textureSize.height * scale;
        break;

      case BoxFit.cover:
        final widthRatio = widgetSize.width / textureSize.width;
        final heightRatio = widgetSize.height / textureSize.height;
        final scale = widthRatio > heightRatio ? widthRatio : heightRatio;
        fittedTextureWidth = textureSize.width * scale;
        fittedTextureHeight = textureSize.height * scale;
        break;

      case BoxFit.fill:
        fittedTextureWidth = widgetSize.width;
        fittedTextureHeight = widgetSize.height;
        break;

      case BoxFit.fitHeight:
        final ratio = widgetSize.height / textureSize.height;
        fittedTextureWidth = textureSize.width * ratio;
        fittedTextureHeight = widgetSize.height;
        break;

      case BoxFit.fitWidth:
        final ratio = widgetSize.width / textureSize.width;
        fittedTextureWidth = widgetSize.width;
        fittedTextureHeight = textureSize.height * ratio;
        break;

      case BoxFit.none:
      case BoxFit.scaleDown:
        fittedTextureWidth = textureSize.width;
        fittedTextureHeight = textureSize.height;
        break;
    }

    final offsetX = (widgetSize.width - fittedTextureWidth) / 2;
    final offsetY = (widgetSize.height - fittedTextureHeight) / 2;

    final left = (scanWindow.left - offsetX) / fittedTextureWidth;
    final top = (scanWindow.top - offsetY) / fittedTextureHeight;
    final right = (scanWindow.right - offsetX) / fittedTextureWidth;
    final bottom = (scanWindow.bottom - offsetY) / fittedTextureHeight;

    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect? scanWindow;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return ValueListenableBuilder<MobileScannerArguments?>(
      valueListenable: _controller.startArguments,
      builder: (context, value, child) {
        if (value == null) {
          return _buildPlaceholderOrError(context, child);
        }

        if (widget.scanWindow != null && scanWindow == null) {
          scanWindow = calculateScanWindowRelativeToTextureInPercentage(
            widget.fit,
            widget.scanWindow!,
            value.size,
            size,
          );

          _controller.updateScanWindow(scanWindow);
        }
        if (widget.overlay != null) {
          return Stack(
            alignment: Alignment.center,
            children: [
              _scanner(value.size, value.webId, value.textureId),
              widget.overlay!
            ],
          );
        } else {
          return _scanner(value.size, value.webId, value.textureId);
        }
      },
    );
  }

  Widget _scanner(Size size, String? webId, int? textureId) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (_, constraints) {
          return SizedBox.fromSize(
            size: constraints.biggest,
            child: FittedBox(
              fit: widget.fit,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: kIsWeb
                    ? HtmlElementView(viewType: webId!)
                    : Texture(textureId: textureId!),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.updateScanWindow(null);
    WidgetsBinding.instance.removeObserver(this);
    _barcodesSubscription?.cancel();
    _barcodesSubscription = null;
    _controller.dispose();
    super.dispose();
  }
}
