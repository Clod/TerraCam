import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

class GuidanceScreen extends StatefulWidget {
  const GuidanceScreen({super.key});

  @override
  State<GuidanceScreen> createState() => _GuidanceScreenState();
}

class _GuidanceScreenState extends State<GuidanceScreen> {
  // Camera state
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  XFile? _goldenImage;

  // Sensor state
  StreamSubscription? _sensorsSubscription;
  double _pitch = 0.0;
  double _roll = 0.0;

  // Target state (from the "golden image")
  double? _targetPitch;
  double? _targetRoll;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeSensors();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final firstCamera = cameras.first;

    _cameraController = CameraController(
      firstCamera,
      ResolutionPreset.high,
      enableAudio: false, // We don't need audio
    );

    _initializeControllerFuture = _cameraController!.initialize();
    setState(() {}); // Update the UI
  }

  void _initializeSensors() {
    _sensorsSubscription = accelerometerEvents.listen((
      AccelerometerEvent event,
    ) {
      // Simple algorithm to calculate pitch and roll from accelerometer data
      // This gives a good approximation for a top-down orientation
      final double pitchRad = math.atan2(
        -event.x,
        math.sqrt(event.y * event.y + event.z * event.z),
      );
      final double rollRad = math.atan2(event.y, event.z);

      if (mounted) {
        setState(() {
          _pitch = vector.degrees(pitchRad);
          _roll = vector.degrees(rollRad);
        });
      }
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _sensorsSubscription?.cancel();
    super.dispose();
  }

  void _setGoldenImage() async {
    try {
      await _initializeControllerFuture;
      final image = await _cameraController!.takePicture();

      setState(() {
        _goldenImage = image;
        // Set the current pitch and roll as the target to match
        _targetPitch = _pitch;
        _targetRoll = _roll;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Golden Image and Target Angles Set!')),
      );
    } catch (e) {
      debugPrint("Error taking picture: $e");
    }
  }

  void _clearGoldenImage() {
    setState(() {
      _goldenImage = null;
      _targetPitch = null;
      _targetRoll = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guidance Prototype'),
        backgroundColor: Colors.black45,
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            // Main UI Stack
            return Stack(
              fit: StackFit.expand,
              children: [
                // Layer 1: Camera Preview
                CameraPreview(_cameraController!),

                // Layer 2: Ghost Image Overlay
                if (_goldenImage != null)
                  Opacity(
                    opacity: 0.4,
                    child: Image.file(
                      File(_goldenImage!.path),
                      fit: BoxFit.cover,
                    ),
                  ),

                // Layer 3: Framing Guide (Placeholder)
                Center(
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.9,
                    height: MediaQuery.of(context).size.height * 0.7,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.yellow.withOpacity(0.7),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),

                // Layer 4: UI Information and Controls
                SafeArea(child: _buildControlsAndInfoUI()),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }

  Widget _buildControlsAndInfoUI() {
    final bool isPitchAligned =
        _targetPitch != null && (_pitch - _targetPitch!).abs() < 2.0;
    final bool isRollAligned =
        _targetRoll != null && (_roll - _targetRoll!).abs() < 2.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Top Info Panel for Angles
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.black.withOpacity(0.5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildAngleIndicator(
                "Pitch",
                _pitch,
                _targetPitch,
                isPitchAligned,
              ),
              _buildAngleIndicator("Roll", _roll, _targetRoll, isRollAligned),
            ],
          ),
        ),

        // Bottom Control Panel
        Container(
          padding: const EdgeInsets.all(16.0),
          color: Colors.black.withOpacity(0.5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: _setGoldenImage,
                child: const Text('Set Golden Image'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: _clearGoldenImage,
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAngleIndicator(
    String name,
    double value,
    double? target,
    bool isAligned,
  ) {
    Color indicatorColor = Colors.white;
    if (target != null) {
      indicatorColor = isAligned ? Colors.greenAccent : Colors.orangeAccent;
    }

    return Column(
      children: [
        Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${value.toStringAsFixed(1)}°',
          style: TextStyle(color: indicatorColor, fontSize: 18),
        ),
        if (target != null)
          Text(
            'Target: ${target.toStringAsFixed(1)}°',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
      ],
    );
  }
}
