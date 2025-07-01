import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'package:gal/gal.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// A screen that provides guidance for taking photos from a specific angle and position.
///
/// This widget displays a camera preview and uses the device's accelerometer to
/// guide the user to match a previously set "golden" orientation (pitch and roll).
/// It allows setting a reference image and then overlays it as a "ghost" to help
/// align the new shot.
class GuidanceScreen extends StatefulWidget {
  /// Creates a const instance of [GuidanceScreen].
  const GuidanceScreen({super.key});

  @override
  State<GuidanceScreen> createState() => _GuidanceScreenState();
}

class _GuidanceScreenState extends State<GuidanceScreen> {
  // Camera-related state variables.
  /// The controller for the device's camera. It manages camera functionalities
  /// like preview, focus, and taking pictures.
  CameraController? _cameraController;
  /// A future that completes when the camera controller is fully initialized.
  /// This is used by a FutureBuilder to show a loading indicator until the camera is ready.
  Future<void>? _initializeControllerFuture;
  /// The file containing the "golden" or reference image. When set, this image
  /// is displayed as a semi-transparent overlay on the camera preview.
  XFile? _goldenImage;

  // Sensor-related state variables.
  /// The subscription to the device's accelerometer events stream.
  /// This needs to be cancelled in `dispose` to prevent memory leaks.
  StreamSubscription? _sensorsSubscription;
  /// The current pitch of the device in degrees. Pitch represents the rotation
  /// around the horizontal axis (X-axis).
  double _pitch = 0.0;
  /// The current roll of the device in degrees. Roll represents the rotation
  /// around the longitudinal axis (Z-axis).
  double _roll = 0.0;

  // Target orientation state variables (derived from the "golden image" moment).
  /// The target pitch in degrees that the user should match. This is set when
  /// the golden image is taken.
  double? _targetPitch;
  /// The target roll in degrees that the user should match. This is set when
  /// the golden image is taken.
  double? _targetRoll;

  /// A threshold for blur detection. If the variance of the Laplacian is below
  /// this value, the image is considered blurry. This value may need tuning.
  final double _blurThreshold = 100.0;

  @override
  void initState() {
    super.initState();
    // Initialize camera and sensors when the widget is first created.
    _initializeCamera();
    _initializeSensors();
  }

  /// Initializes the camera controller.
  ///
  /// This method finds the available cameras, selects the first one, creates a
  /// [CameraController], and then starts the initialization process. The future
  /// for this process is stored in [_initializeControllerFuture].
  Future<void> _initializeCamera() async {
    // Obtain a list of the available cameras on the device.
    final cameras = await availableCameras();
    // Get a specific camera from the list of available cameras.
    final firstCamera = cameras.first;

    _cameraController = CameraController(
      firstCamera,
      ResolutionPreset.high,
      enableAudio: false, // We don't need audio
    );

    // Initialize the controller. This returns a Future.
    _initializeControllerFuture = _cameraController!.initialize();
    // Call setState to rebuild the widget tree, which will now use the
    // FutureBuilder to wait for the controller to initialize.
    setState(() {});
  }

  /// Initializes the sensor stream listener.
  ///
  /// This method subscribes to the accelerometer event stream to get real-time
  /// data about the device's orientation. It then calculates the pitch and roll
  /// and updates the state.
  void _initializeSensors() {
    // Listen to the stream of accelerometer events.
    _sensorsSubscription = accelerometerEventStream().listen((
      AccelerometerEvent event,
    ) {
      // A simple algorithm to calculate pitch and roll from accelerometer data.
      // This provides a reasonable approximation, especially when the device is
      // pointed downwards (top-down view).
      // atan2 is used to get the angle in radians from the accelerometer readings.
      final double pitchRad = math.atan2(
        -event.x,
        math.sqrt(event.y * event.y + event.z * event.z),
      );
      final double rollRad = math.atan2(event.y, event.z);

      // Check if the widget is still in the widget tree before calling setState.
      if (mounted) {
        // Update the state with the new pitch and roll values, converted from radians to degrees.
        setState(() {
          _pitch = vector.degrees(pitchRad);
          _roll = vector.degrees(rollRad);
        });
      }
    });
  }

  /// Checks if the given image is blurry by calculating the variance of its Laplacian.
  ///
  /// A low variance suggests that there are not many edges in the image, which
  /// is characteristic of a blurry photo.
  ///
  /// [imageFile]: The image to be analyzed.
  /// Returns a `Future<bool>` which is `true` if the image is blurry, `false` otherwise.
  Future<bool> _isImageBlurry(XFile imageFile) async {
    debugPrint("Starting blur check for ${imageFile.path}");
    try {
      // 1. Read image bytes from the temporary file.
      final Uint8List imageBytes = await imageFile.readAsBytes();
      debugPrint("Image bytes read: ${imageBytes.length} bytes");

      // 2. Decode image to OpenCV's Mat format.
      // The image is decoded as a color image.
      final img = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
      if (img == null || img.isEmpty) {
        debugPrint("Failed to decode image for blur check.");
        return false; // Can't determine, assume not blurry to avoid blocking user.
      }
      debugPrint("Image decoded successfully. Size: ${img.width}x${img.height}");

      // 3. Convert the image to grayscale for easier edge detection.
      final gray = cv.cvtColor(img, cv.COLOR_BGR2GRAY);
      debugPrint("Image converted to grayscale.");

      // 4. Apply the Laplacian operator to the grayscale image.
      // This operator highlights regions of rapid intensity change (i.e., edges).
      // A blurry image will have less pronounced edges.
      // The ddepth parameter is set to CV_64F (a float type) to avoid overflow.
      // Using the integer value 6, as some environments might have trouble resolving the cv.CV_64F constant.
      final laplacian = cv.laplacian(gray, 6 /* cv.CV_64F */);
      debugPrint("Laplacian filter applied.");

      // 5. Calculate the variance of the Laplacian image.
      // A higher variance indicates more edges and a sharper image.
      // meanStdDev returns a (Scalar, Scalar) record for mean and stddev.
      final meanStdDev = cv.meanStdDev(laplacian);
      // We access the stddev scalar with .$2 and get its first value.
      final double stdDev = meanStdDev.$2.val1;
      final double variance = stdDev * stdDev;

      debugPrint("Image Laplacian variance: $variance");

      // 6. Compare the variance to a predefined threshold.
      final bool isBlurry = variance < _blurThreshold;
      debugPrint("Image is blurry: $isBlurry (Threshold: $_blurThreshold)");
      return isBlurry;
    } catch (e, s) {
      debugPrint("!!! ERROR checking for blur: $e");
      debugPrint("!!! Stack trace: $s");
      // If an error occurs during the check, assume it's not blurry
      // to not block the user from taking a photo.
      return false;
    }
  }

  /// Takes a picture and saves it to the device's gallery.
  ///
  /// This function is typically triggered by a user action, like pressing a button.
  /// It ensures the camera is ready, takes a photo, and uses the `gal` package
  /// to save it. It also provides user feedback via SnackBars.
  void _takePhotoAndSave() async {
    debugPrint("--- _takePhotoAndSave called ---");
    try {
      // Wait for the camera controller to be initialized.
      await _initializeControllerFuture;
      if (!_cameraController!.value.isInitialized) {
        debugPrint("Cámara no inicializada o no disponible.");
        return;
      }

      // Take the picture and get the file.
      final XFile image = await _cameraController!.takePicture();
      debugPrint("Picture taken, temporary path: ${image.path}");

      // Check if the image is blurry before saving.
      if (await _isImageBlurry(image)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Imagen borrosa. Intente de nuevo.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        // Do not save the blurry photo.
        return;
      }

      // Save the image from its temporary path to the device's public gallery.
      await Gal.putImage(image.path);

      // If the widget is still mounted, show a success message.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto guardada en la galería')),
        );
      }
    } catch (e, s) {
      // If an error occurs, print it to the console and show an error message.
      debugPrint("!!! Error in _takePhotoAndSave: $e");
      debugPrint("!!! Stack trace: $s");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error guardando foto: $e')));
      }
    }
  }

  @override
  void dispose() {
    // Dispose of the camera controller to release camera resources.
    _cameraController?.dispose();
    // Cancel the sensor stream subscription to prevent memory leaks.
    _sensorsSubscription?.cancel();
    super.dispose();
  }

  /// Sets the current camera view and orientation as the "golden" reference.
  ///
  /// This function takes a picture to be used as a semi-transparent overlay
  /// and captures the current pitch and roll values as the target orientation
  /// for the user to match in subsequent photos.
  void _setGoldenImage() async {
    debugPrint("--- _setGoldenImage called ---");
    try {
      // Ensure the camera is initialized before proceeding.
      await _initializeControllerFuture;

      // Add a check to ensure the camera is initialized, similar to _takePhotoAndSave.
      if (!_cameraController!.value.isInitialized) {
        debugPrint("Cámara no inicializada o no disponible.");
        return;
      }

      // Take a picture.
      final image = await _cameraController!.takePicture();

      // After an asynchronous operation, it's crucial to check if the widget
      // is still mounted before updating its state or accessing its context.
      if (!mounted) return;

      final bool isBlurry = await _isImageBlurry(image);

      // Check mounted status again after the async blur check.
      if (!mounted) return;

      // Check if the reference image is blurry.
      if (isBlurry) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('La imagen de referencia está borrosa. Intente de nuevo.'),
            backgroundColor: Colors.orange,
          ),
        );
        // Do not set a blurry photo as the reference.
        return;
      }

      // Update the state with the new golden image and target angles.
      setState(() {
        _goldenImage = image;
        // Set the current pitch and roll as the target to match.
        _targetPitch = _pitch;
        _targetRoll = _roll;
      });

      // Show a confirmation message to the user.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagen de referencia establecida.')),
      );
    } catch (e, s) {
      // Handle any errors during the process.
      debugPrint("!!! Error in _setGoldenImage: $e");
      debugPrint("!!! Stack trace: $s");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error setting reference: $e')));
      }
    }
  }

  /// Clears the golden image and resets the target angles.
  ///
  /// This allows the user to remove the reference overlay and start over.
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
        title: const Text('TerraCam '),
        backgroundColor: Colors.black45,
      ),
      // Use a FutureBuilder to handle the asynchronous initialization of the camera.
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          // If the Future is complete, the camera is initialized.
          if (snapshot.connectionState == ConnectionState.done) {
            // Use a Stack to overlay widgets on top of the camera preview.
            return Stack(
              fit: StackFit.expand, // Make children of the stack fill the screen.
              children: [
                // Layer 1: The live camera preview.
                CameraPreview(_cameraController!),

                // Layer 2: The "ghost" image overlay.
                // This is only visible if a golden image has been set.
                if (_goldenImage != null)
                  Opacity(
                    opacity: 0.4, // Make the image semi-transparent.
                    child: Image.file(
                      File(_goldenImage!.path), // Load image from the file path.
                      fit: BoxFit.cover, // Cover the entire screen space.
                    ),
                  ),

                // Layer 3: UI elements like controls and information displays.
                // SafeArea ensures the UI doesn't overlap with system UI (like notches).
                SafeArea(child: _buildControlsAndInfoUI()),
              ],
            );
          } else {
            // While the camera is initializing, show a loading spinner.
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }

  /// Builds the main UI, including angle indicators, framing guide, and control buttons.
  Widget _buildControlsAndInfoUI() {
    // Determine if the current pitch is aligned with the target pitch.
    // A tolerance of 2.0 degrees is used.
    final bool isPitchAligned =
        _targetPitch != null && (_pitch - _targetPitch!).abs() < 2.0;
    // Determine if the current roll is aligned with the target roll.
    final bool isRollAligned =
        _targetRoll != null && (_roll - _targetRoll!).abs() < 2.0;

    return Column(
      children: [
        // Top Info Panel for displaying current and target angles.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.black.withAlpha(128), // Semi-transparent background.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildAngleIndicator(
                "Eje menor",
                _pitch,
                _targetPitch,
                isPitchAligned,
              ),
              _buildAngleIndicator(
                "Eje mayor",
                _roll,
                _targetRoll,
                isRollAligned,
              ),
            ],
          ),
        ),

        // The framing guide will take up the remaining vertical space.
        Expanded(child: _buildFramingGuide()),

        // Bottom Control Panel with action buttons.
        Container(
          padding: const EdgeInsets.all(16.0),
          color: Colors.black.withAlpha(128), // Semi-transparent background.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Button to set the golden/reference image.
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: _setGoldenImage,
                child: const Text('Referencia'),
              ),
              // Button to take a photo and save it.
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: _takePhotoAndSave,
                child: const Text('Click'),
              ),
              // Button to clear the reference image and target angles.
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: _clearGoldenImage,
                child: const Text('Reset'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds a rectangular framing guide overlay.
  ///
  /// This helps the user to frame their shot correctly. The aspect ratio is
  /// set to match that of an A3 paper sheet in portrait orientation.
  Widget _buildFramingGuide() {
    // A3 paper aspect ratio (portrait) is 297mm (width) / 420mm (height).
    const a3AspectRatio = 297 / 420;

    return Padding(
      // Add padding to ensure the guide doesn't touch the screen edges or UI elements.
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: AspectRatio(
        aspectRatio: a3AspectRatio,
        child: Container(
          decoration: BoxDecoration(
            // A semi-transparent yellow border to make the guide visible.
            border: Border.all(color: Colors.yellow.withAlpha(179), width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  /// Builds a widget to display a single angle's information.
  ///
  /// This includes the angle's name, its current value, and its target value (if set).
  /// The color of the current value changes to indicate alignment status.
  Widget _buildAngleIndicator(
    String name,
    double value,
    double? target,
    bool isAligned,
  ) {
    // Default color for the text is white.
    Color indicatorColor = Colors.white;
    // If a target is set, change the color based on alignment.
    if (target != null) {
      indicatorColor = isAligned ? Colors.greenAccent : Colors.orangeAccent;
    }

    return Column(
      children: [
        // The name of the angle (e.g., "Eje menor").
        Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        // The current value of the angle, with color indicating alignment.
        Text(
          '${value.toStringAsFixed(1)}°',
          style: TextStyle(color: indicatorColor, fontSize: 18),
        ),
        // If a target is set, display it for reference.
        if (target != null)
          Text(
            'Target: ${target.toStringAsFixed(1)}°',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
      ],
    );
  }
}
