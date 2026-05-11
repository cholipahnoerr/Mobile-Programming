import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MaterialApp(
    home: MangoDetector(camera: cameras.first),
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
    ),
  ));
}

class ClassResult {
  final String label;
  final double confidence;
  ClassResult({required this.label, required this.confidence});
}

class DetectionResult {
  final String topLabel;
  final double topConfidence;
  final bool isMango;
  final List<ClassResult> all;

  DetectionResult({
    required this.topLabel,
    required this.topConfidence,
    required this.isMango,
    required this.all,
  });
}

class MangoDetector extends StatefulWidget {
  final CameraDescription camera;
  const MangoDetector({super.key, required this.camera});

  @override
  State<MangoDetector> createState() => _MangoDetectorState();
}

class _MangoDetectorState extends State<MangoDetector> {
  late CameraController _controller;
  Interpreter? _interpreter;
  List<String> _labels = [];
  DetectionResult? _liveResult;
  bool _isProcessing = false;
  bool _modelLoaded = false;
  bool _isCapturing = false;
  final ImagePicker _picker = ImagePicker();
  static const double _threshold = 0.6;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.medium);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _startLiveDetection();
    });
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      final bundle = DefaultAssetBundle.of(context);
      _interpreter = await Interpreter.fromAsset('assets/model_mangga.tflite');
      final raw = await bundle.loadString('assets/labels.txt');
      _labels = raw.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (mounted) setState(() => _modelLoaded = true);
    } catch (e) {
      debugPrint('Model load error: $e');
    }
  }

  void _startLiveDetection() {
    _controller.startImageStream((frame) async {
      if (_isProcessing || !_modelLoaded || _isCapturing) return;
      _isProcessing = true;
      try {
        final result = _runInference(_convertCameraImage(frame));
        if (mounted) setState(() => _liveResult = result);
      } catch (e) {
        debugPrint('Live detection error: $e');
      } finally {
        _isProcessing = false;
      }
    });
  }

  // Unified inference — called from live, capture, and gallery paths
  DetectionResult _runInference(img.Image image) {
    if (_interpreter == null || _labels.isEmpty) {
      return DetectionResult(topLabel: 'Model belum siap', topConfidence: 0, isMango: false, all: []);
    }

    final resized = img.copyResize(image, width: 224, height: 224);
    final input = List.generate(1, (_) =>
        List.generate(224, (y) =>
            List.generate(224, (x) {
              final p = resized.getPixel(x, y);
              return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
            })));

    final n = _labels.length;
    final output = List.filled(n, 0.0).reshape([1, n]);
    _interpreter!.run(input, output);

    final scores = List<double>.from(output[0] as List);
    final all = List.generate(n, (i) => ClassResult(label: _labels[i], confidence: scores[i]))
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final top = all.first;
    final isNonMango = top.label.toLowerCase() == 'non_mango';
    final isMango = !isNonMango && top.confidence >= _threshold;

    return DetectionResult(
      topLabel: isMango ? top.label : 'Bukan Mangga',
      topConfidence: top.confidence,
      isMango: isMango,
      all: all,
    );
  }

  // ── Image conversion ─────────────────────────────────────────────────────

  img.Image _convertCameraImage(CameraImage frame) {
    if (frame.format.group == ImageFormatGroup.yuv420) {
      return _fromYUV420(frame);
    } else if (frame.format.group == ImageFormatGroup.bgra8888) {
      return _fromBGRA8888(frame);
    }
    // fallback: Y-only (grayscale)
    final y = frame.planes[0].bytes;
    final w = frame.width;
    final h = frame.height;
    final out = img.Image(width: w, height: h);
    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final v = y[row * w + col];
        out.setPixelRgba(col, row, v, v, v, 255);
      }
    }
    return out;
  }

  // YUV420 → RGB (Android)
  img.Image _fromYUV420(CameraImage frame) {
    final w = frame.width;
    final h = frame.height;
    final out = img.Image(width: w, height: h);

    final yBytes = frame.planes[0].bytes;
    final uBytes = frame.planes[1].bytes;
    final vBytes = frame.planes[2].bytes;
    final yStride = frame.planes[0].bytesPerRow;
    final uStride = frame.planes[1].bytesPerRow;
    final uPixel = frame.planes[1].bytesPerPixel ?? 1;
    final vStride = frame.planes[2].bytesPerRow;
    final vPixel = frame.planes[2].bytesPerPixel ?? 1;

    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final yVal = yBytes[row * yStride + col];
        final uvRow = row ~/ 2;
        final uvCol = col ~/ 2;
        final uVal = uBytes[uvRow * uStride + uvCol * uPixel];
        final vVal = vBytes[uvRow * vStride + uvCol * vPixel];

        final r = (yVal + 1.402 * (vVal - 128)).round().clamp(0, 255);
        final g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).round().clamp(0, 255);
        final b = (yVal + 1.772 * (uVal - 128)).round().clamp(0, 255);

        out.setPixelRgba(col, row, r, g, b, 255);
      }
    }
    return out;
  }

  // BGRA8888 → RGB (iOS)
  img.Image _fromBGRA8888(CameraImage frame) {
    final bytes = frame.planes[0].bytes;
    final w = frame.width;
    final h = frame.height;
    final out = img.Image(width: w, height: h);
    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final i = (row * w + col) * 4;
        out.setPixelRgba(col, row, bytes[i + 2], bytes[i + 1], bytes[i], 255);
      }
    }
    return out;
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _captureAndDetect() async {
    if (!_modelLoaded) {
      _showNotReady();
      return;
    }
    setState(() => _isCapturing = true);
    try {
      await _controller.stopImageStream();
      final file = await _controller.takePicture();
      final decoded = img.decodeImage(await File(file.path).readAsBytes());
      if (decoded != null && mounted) {
        _showResultDialog(file.path, _runInference(decoded), title: 'Hasil Deteksi');
      }
    } catch (e) {
      debugPrint('Capture error: $e');
    } finally {
      setState(() => _isCapturing = false);
      _startLiveDetection();
    }
  }

  Future<void> _pickFromGallery() async {
    if (!_modelLoaded) {
      _showNotReady();
      return;
    }
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      final decoded = img.decodeImage(await File(picked.path).readAsBytes());
      if (decoded != null && mounted) {
        _showResultDialog(picked.path, _runInference(decoded), title: 'Hasil Deteksi Galeri');
      }
    } catch (e) {
      debugPrint('Gallery error: $e');
    }
  }

  void _showNotReady() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Model AI sedang dimuat, tunggu sebentar...')),
    );
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  Color _colorFor(String label) {
    final l = label.toLowerCase();
    if (l == 'bukan mangga' || l == 'non_mango') return Colors.grey;
    if (l.contains('ripe') && !l.contains('raw')) return Colors.green;
    if (l.contains('raw') && l.contains('ripe')) return Colors.lightGreen;
    if (l == 'rawmango' || l == 'raw mango') return Colors.amber;
    if (l.contains('bad')) return Colors.redAccent;
    return Colors.orange;
  }

  IconData _iconFor(String label) {
    final l = label.toLowerCase();
    if (l == 'bukan mangga' || l == 'non_mango') return Icons.block;
    if (l.contains('ripe') && !l.contains('raw')) return Icons.check_circle;
    if (l.contains('raw')) return Icons.schedule;
    if (l.contains('bad')) return Icons.cancel;
    return Icons.help_outline;
  }

  Widget _confidenceBar(ClassResult r) {
    final color = _colorFor(r.label);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(r.label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text(
                '${(r.confidence * 100).toStringAsFixed(1)}%',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: r.confidence,
              minHeight: 6,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  void _showResultDialog(String imagePath, DetectionResult result, {required String title}) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(imagePath),
                    height: 200, width: double.infinity, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_iconFor(result.topLabel), color: _colorFor(result.topLabel), size: 26),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      result.topLabel,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _colorFor(result.topLabel),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${(result.topConfidence * 100).toStringAsFixed(1)}% confidence',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const Divider(color: Colors.white24, height: 24),
              ...result.all.map(_confidenceBar),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tutup'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _controller.dispose();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mango Maturity Detector'),
        centerTitle: true,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Tooltip(
              message: _modelLoaded ? 'Model siap' : 'Memuat model...',
              child: Icon(
                _modelLoaded ? Icons.memory : Icons.hourglass_bottom,
                color: _modelLoaded ? Colors.greenAccent : Colors.orange,
                size: 22,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          CameraPreview(_controller),

          // Live overlay
          Positioned(
            top: 16, left: 16, right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _buildLiveOverlay(),
            ),
          ),

          // Bottom panel
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isCapturing ? null : _pickFromGallery,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Galeri'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[700],
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.blue[900],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isCapturing ? null : _captureAndDetect,
                      icon: _isCapturing
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.camera_alt),
                      label: Text(_isCapturing ? 'Memproses...' : 'Capture'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange[700],
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.orange[900],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveOverlay() {
    if (!_modelLoaded) {
      return const Row(
        children: [
          SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)),
          SizedBox(width: 10),
          Text('Memuat model AI...', style: TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      );
    }

    if (_liveResult == null) {
      return const Text('Mendeteksi...', style: TextStyle(color: Colors.white54, fontSize: 13));
    }

    final result = _liveResult!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(_iconFor(result.topLabel), color: _colorFor(result.topLabel), size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                result.topLabel,
                style: TextStyle(
                  color: _colorFor(result.topLabel),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              '${(result.topConfidence * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                color: _colorFor(result.topLabel),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Top 3 bars
        ...result.all.take(3).map(_confidenceBar),
      ],
    );
  }
}
