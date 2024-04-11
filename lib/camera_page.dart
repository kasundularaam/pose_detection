// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:vector_math/vector_math.dart' as vm;

class CameraPage extends StatelessWidget {
  const CameraPage({super.key});

  Future<CameraController> loadController() async {
    final cameras = await availableCameras();
    final firstCamera = cameras[1];
    final controller = CameraController(
      firstCamera,
      ResolutionPreset.veryHigh,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await controller.initialize();
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("With Camera"),
      ),
      body: FutureBuilder(
        future: loadController(),
        builder: (context, AsyncSnapshot<CameraController> snapshot) {
          if (snapshot.hasData) {
            final controller = snapshot.data;
            if (controller == null) {
              return const Text('No camera found.');
            }
            return CamView(controller: controller);
          }
          if (snapshot.hasError) {
            return Text(snapshot.error.toString());
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

class CamView extends StatefulWidget {
  final CameraController controller;

  const CamView({super.key, required this.controller});

  @override
  State<CamView> createState() => _CamViewState();
}

class _CamViewState extends State<CamView> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CameraPreview(widget.controller),
        StreamBuilder(
            stream: DetectPoseService.init(context, widget.controller)
                .detectLandmarks(),
            builder: (context,
                AsyncSnapshot<Map<PoseLandmarkType, PoseLandmark>?> snapshot) {
              if (snapshot.hasData) {
                final pose = snapshot.data;
                if (pose == null) {
                  return const Text('No pose detected.');
                }
                final values = pose.values.toList();
                return Stack(
                  children: List<Widget>.generate(
                    values.length,
                    (index) {
                      return Positioned(
                        right: values[index].x,
                        top: values[index].y,
                        child: Container(
                          width: 10,
                          height: 10,
                          color: Colors.red,
                        ),
                      );
                    },
                  ),
                );
              }
              if (snapshot.hasError) {
                return Text(snapshot.error.toString());
              }
              return const Center(child: CircularProgressIndicator());
            }),
      ],
    );
  }
}

class DetectPoseService {
  final CameraController controller;
  final BuildContext context;
  final double scale;
  final poseDetector = PoseDetector(options: PoseDetectorOptions());

  DetectPoseService(
      {required this.controller, required this.context, required this.scale});

  factory DetectPoseService.init(
      BuildContext context, CameraController controller) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final imageWidth = controller.value.previewSize!.height;
    return DetectPoseService(
        controller: controller,
        context: context,
        scale: screenWidth / imageWidth);
  }

  Stream<Map<PoseLandmarkType, PoseLandmark>?> detectLandmarks() async* {
    yield* _imageStream().asyncMap((image) async {
      final inputImage = _inputImage(image);
      if (inputImage == null) {
        return null;
      }
      Stopwatch stopwatch = Stopwatch()..start();
      final poses = await poseDetector.processImage(inputImage);
      stopwatch.stop();
      if (poses.isEmpty) {
        return null;
      }
      log("fetchData executed in ${stopwatch.elapsedMilliseconds} milliseconds");
      final landmarks = poses[0].landmarks;
      log(calculateBodyPoseData(landmarks).toString());
      return landmarks.map((key, value) =>
          MapEntry<PoseLandmarkType, PoseLandmark>(
              key, _scaledLandmark(value)));
    });
  }

  BodyPoseData calculateBodyPoseData(
      Map<PoseLandmarkType, PoseLandmark>? landmarks) {
    // Handle potential missing landmarks
    if (landmarks == null) {
      throw ArgumentError("landmarks cannot be null");
    }

    final nose = landmarks[PoseLandmarkType.nose];
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
    final leftElbow = landmarks[PoseLandmarkType.leftElbow];
    final rightElbow = landmarks[PoseLandmarkType.rightElbow];
    final leftWrist = landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = landmarks[PoseLandmarkType.rightWrist];

    // Ensure required landmarks are present
    if (nose == null ||
        leftShoulder == null ||
        rightShoulder == null ||
        leftElbow == null ||
        rightElbow == null ||
        leftWrist == null ||
        rightWrist == null) {
      throw ArgumentError("Missing required landmarks");
    }

    // Calculate Relative Coordinates
    vm.Vector2 calculateRelativeCoordinate(PoseLandmark landmark) {
      return vm.Vector2(landmark.x - nose.x, landmark.y - nose.y);
    }

    // Calculate angles
    int calculateAngle(vm.Vector2 v1, vm.Vector2 v2) {
      return vm.degrees(v1.angleTo(v2)).round();
    }

    // Create BodyPoseData object
    return BodyPoseData(
      leftShoulderElbowAngle: calculateAngle(
        calculateRelativeCoordinate(leftElbow),
        calculateRelativeCoordinate(leftShoulder),
      ),
      leftElbowWristAngle: calculateAngle(
        calculateRelativeCoordinate(leftWrist),
        calculateRelativeCoordinate(leftElbow),
      ),
      rightShoulderElbowAngle: calculateAngle(
        calculateRelativeCoordinate(rightElbow),
        calculateRelativeCoordinate(rightShoulder),
      ),
      rightShoulderLeftShoulder: calculateAngle(
        calculateRelativeCoordinate(leftShoulder),
        calculateRelativeCoordinate(rightShoulder),
      ),
      rightElbowWristAngle: calculateAngle(
        calculateRelativeCoordinate(rightWrist),
        calculateRelativeCoordinate(rightElbow),
      ),
      leftShoulderXRel: calculateRelativeCoordinate(leftShoulder).x,
      leftShoulderYRel: calculateRelativeCoordinate(leftShoulder).y,
      leftElbowXRel: calculateRelativeCoordinate(leftElbow).x,
      leftElbowYRel: calculateRelativeCoordinate(leftElbow).y,
      leftWristXRel: calculateRelativeCoordinate(leftWrist).x,
      leftWristYRel: calculateRelativeCoordinate(leftWrist).y,
      rightShoulderXRel: calculateRelativeCoordinate(rightShoulder).x,
      rightShoulderYRel: calculateRelativeCoordinate(rightShoulder).y,
      rightElbowXRel: calculateRelativeCoordinate(rightElbow).x,
      rightElbowYRel: calculateRelativeCoordinate(rightElbow).y,
      rightWristXRel: calculateRelativeCoordinate(rightWrist).x,
      rightWristYRel: calculateRelativeCoordinate(rightWrist).y,
    );
  }

  PoseLandmark _scaledLandmark(PoseLandmark landmark) {
    return PoseLandmark(
      type: landmark.type,
      x: landmark.x * scale,
      y: landmark.y * scale,
      z: landmark.z,
      likelihood: landmark.likelihood,
    );
  }

  Stream<CameraImage> _imageStream() async* {
    int frameCounter = 0;
    const framesToSkip = 1;
    StreamController<CameraImage> streamController = StreamController();
    controller.startImageStream((image) {
      frameCounter++;
      if (frameCounter % framesToSkip == 0) {
        streamController.add(image);
      }
    });
    yield* streamController.stream;
  }

  InputImage? _inputImage(CameraImage image) {
    try {
      InputImageRotation? rotation =
          _calculateImageRotation(image, controller.description, controller);
      if (rotation == null) {
        return null;
      }

      InputImageFormat? format = _validateImageFormat(image.format.raw);
      if (format == null) {
        return null;
      }

      final metadata = _createInputImageMetadata(image, rotation, format);

      final bytes = _extractImageBytes(image);

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);

      return inputImage;
    } catch (e) {
      return null;
    }
  }

  InputImageRotation? _calculateImageRotation(CameraImage image,
      CameraDescription camera, CameraController controller) {
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    final orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      final deviceOrientation =
          orientations[controller.value.deviceOrientation];
      if (deviceOrientation == null) return null;

      if (camera.lensDirection == CameraLensDirection.front) {
        rotation = InputImageRotationValue.fromRawValue(
            (sensorOrientation + deviceOrientation) % 360);
      } else {
        rotation = InputImageRotationValue.fromRawValue(
            (sensorOrientation - deviceOrientation + 360) % 360);
      }
    }

    return rotation;
  }

  InputImageFormat? _validateImageFormat(int rawFormat) {
    InputImageFormat? format = InputImageFormatValue.fromRawValue(rawFormat);
    if (format == InputImageFormat.nv21 ||
        format == InputImageFormat.bgra8888) {
      return format;
    }
    return null;
  }

  InputImageMetadata _createInputImageMetadata(
      CameraImage image, InputImageRotation rotation, InputImageFormat format) {
    return InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );
  }

  Uint8List _extractImageBytes(CameraImage image) {
    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }
}

class BodyPoseData {
  // Angle measurements (use 'int' since angles appear whole-valued)
  final int leftShoulderElbowAngle;
  final int leftElbowWristAngle;
  final int rightShoulderElbowAngle;
  final int rightShoulderLeftShoulder;
  final int rightElbowWristAngle;

  // Relative coordinates (use 'double' for precision)
  final double leftShoulderXRel;
  final double leftShoulderYRel;
  final double leftElbowXRel;
  final double leftElbowYRel;
  final double leftWristXRel;
  final double leftWristYRel;
  final double rightShoulderXRel;
  final double rightShoulderYRel;
  final double rightElbowXRel;
  final double rightElbowYRel;
  final double rightWristXRel;
  final double rightWristYRel;

  // Constructor
  BodyPoseData({
    required this.leftShoulderElbowAngle,
    required this.leftElbowWristAngle,
    required this.rightShoulderElbowAngle,
    required this.rightShoulderLeftShoulder,
    required this.rightElbowWristAngle,
    required this.leftShoulderXRel,
    required this.leftShoulderYRel,
    required this.leftElbowXRel,
    required this.leftElbowYRel,
    required this.leftWristXRel,
    required this.leftWristYRel,
    required this.rightShoulderXRel,
    required this.rightShoulderYRel,
    required this.rightElbowXRel,
    required this.rightElbowYRel,
    required this.rightWristXRel,
    required this.rightWristYRel,
  });

  @override
  String toString() {
    return 'BodyPoseData(leftShoulderElbowAngle: $leftShoulderElbowAngle, leftElbowWristAngle: $leftElbowWristAngle, rightShoulderElbowAngle: $rightShoulderElbowAngle, rightShoulderLeftShoulder: $rightShoulderLeftShoulder, rightElbowWristAngle: $rightElbowWristAngle, leftShoulderXRel: $leftShoulderXRel, leftShoulderYRel: $leftShoulderYRel, leftElbowXRel: $leftElbowXRel, leftElbowYRel: $leftElbowYRel, leftWristXRel: $leftWristXRel, leftWristYRel: $leftWristYRel, rightShoulderXRel: $rightShoulderXRel, rightShoulderYRel: $rightShoulderYRel, rightElbowXRel: $rightElbowXRel, rightElbowYRel: $rightElbowYRel, rightWristXRel: $rightWristXRel, rightWristYRel: $rightWristYRel)';
  }
}
