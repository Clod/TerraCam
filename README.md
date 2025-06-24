# TerraCam: Angle-Guided Photography App

## 1. Overview

TerraCam is a specialized Flutter camera application designed to help users take photographs from a precise and repeatable orientation. The core feature of the app is its ability to guide the user to match a specific **pitch** and **roll** of the device, ensuring that multiple photos can be taken from the exact same angle over time.

This is achieved by first taking a "reference" photo. The application saves the orientation of the device at that moment. For all subsequent photos, the app provides real-time visual feedback, guiding the user to align their device with the saved reference orientation before taking a new picture.

This functionality is particularly useful for:
-   **Scientific Monitoring:** Tracking changes in a specific area, like plant growth or soil erosion, where consistent photo angles are critical.
-   **Construction & Inspection:** Documenting progress or issues from a consistent viewpoint.
-   **Creative Projects:** Creating precise stop-motion animations or before-and-after comparisons.

## 2. Core Features

-   **Live Camera Preview:** Utilizes the device's camera to show a real-time feed.
-   **Reference Image ("Golden Image"):** Users can capture a baseline image. The orientation (pitch and roll) at the moment of capture is saved as the "target orientation."
-   **Ghost Image Overlay:** The captured reference image is displayed as a semi-transparent "ghost" on top of the live camera feed, assisting with positional alignment.
-   **Real-time Angle Guidance:**
    -   The UI displays the device's current pitch and roll, updated continuously using the device's accelerometer.
    -   The target pitch and roll from the reference image are also displayed.
    -   The current angle readings change color (e.g., to green) to provide instant feedback when the device is correctly aligned with the target orientation (within a 2-degree tolerance).
-   **A3 Framing Guide:** An on-screen rectangular overlay with the aspect ratio of an A3 sheet of paper helps users frame their subject consistently.
-   **Save to Gallery:** Photos taken with the app can be saved directly to the device's public photo gallery.
-   **Simple Controls:** Intuitive buttons for setting the reference, taking a photo, and resetting the guidance.

## 3. How It Works: User Flow

1.  **Launch:** The user opens the app and is presented with the camera view.
2.  **Set Reference:** The user points the camera at the subject, frames it as desired, and holds the device at the intended angle. They then press the **"Referencia"** button.
    -   The app takes a picture.
    -   It simultaneously reads the device's current pitch and roll and saves these as the target angles.
    -   The picture is now shown as a transparent overlay (ghost image).
3.  **Align for New Photo:** At a later time, the user wants to take another photo from the same position and angle.
    -   They use the ghost image to align the device's physical position.
    -   They watch the "Eje menor" (Pitch) and "Eje mayor" (Roll) indicators. By tilting the phone, they try to match the current values to the target values.
    -   The numbers turn green when the alignment is correct.
4.  **Capture:** Once perfectly aligned, the user presses the **"Click"** button. The new photo is captured and saved to the gallery.
5.  **Reset:** If the user wants to set a new reference point, they can press the **"Reset"** button, which clears the ghost image and the target angles.

## 4. Technical Implementation

The application is built within a single primary widget, `GuidanceScreen`, which is a `StatefulWidget`.

### Key Components & Logic:

-   **`_GuidanceScreenState`**: Manages the entire state of the screen, including:
    -   Camera controller (`_cameraController`).
    -   Sensor data subscriptions (`_sensorsSubscription`).
    -   Reference image file (`_goldenImage`).
    -   Current and target orientation values (`_pitch`, `_roll`, `_targetPitch`, `_targetRoll`).

-   **Camera Management (`_initializeCamera`)**:
    -   Uses the `camera` package to find available cameras.
    -   Initializes a `CameraController` for the first available camera with a high resolution and audio disabled.
    -   A `FutureBuilder` in the `build` method handles the asynchronous initialization, showing a loading indicator until the camera preview is ready.

-   **Sensor Integration (`_initializeSensors`)**:
    -   Uses the `sensors_plus` package to subscribe to the `accelerometerEventStream`.
    -   On each event, it calculates the pitch and roll using `math.atan2`. This mathematical approach provides a good approximation of the device's tilt based on the force of gravity detected by the accelerometer.
    -   The pitch and roll values are converted from radians to degrees and the state is updated, causing the UI to rebuild with the new angle information.

-   **UI Construction (`build` method)**:
    -   A `Stack` widget is used to layer the UI elements:
        1.  **Base Layer:** `CameraPreview` shows the live feed.
        2.  **Middle Layer:** An `Opacity` widget containing the `_goldenImage` (if set) creates the ghosting effect.
        3.  **Top Layer:** The main UI, including the angle indicators, framing guide, and control buttons.

-   **UI Widgets**:
    -   **`_buildControlsAndInfoUI`**: The main layout widget containing the top info panel and bottom control panel. It determines if the current angles are aligned with the target and passes this information down to the indicators.
    -   **`_buildAngleIndicator`**: A reusable widget that displays the name of an axis (e.g., "Eje menor"), its current value, and its target value. It dynamically changes the text color to signal alignment.
    -   **`_buildFramingGuide`**: A simple `AspectRatio` widget with a decorated `Container` to draw the yellow rectangular guide on the screen.

## 5. Dependencies

This project relies on the following key packages from `pub.dev`:

-   **`camera`**: For direct access and control over the device's camera hardware.
-   **`sensors_plus`**: To access data from the device's motion sensors (specifically the accelerometer).
-   **`gal`**: A simple utility to save image files to the device's public gallery on both iOS and Android.
-   **`vector_math`**: Provides utility functions for vector and matrix math, used here for converting radians to degrees.

## 6. How to Run the Project

1.  **Prerequisites:** Ensure you have the Flutter SDK installed and a configured editor (like VS Code or Android Studio).
2.  **Clone the Repository:**
    ```sh
    git clone <repository-url>
    cd terra_camera
    ```
3.  **Install Dependencies:**
    ```sh
    flutter pub get
    ```
4.  **Configure Permissions:**
    -   **Android:** Ensure `CAMERA` and storage permissions are requested in `android/app/src/main/AndroidManifest.xml`.
    -   **iOS:** Add keys for `NSCameraUsageDescription` and `NSPhotoLibraryAddUsageDescription` to `ios/Runner/Info.plist`.
5.  **Run the App:**
    ```sh
    flutter run
    ```

---