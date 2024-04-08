import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image_picker/image_picker.dart';

class SelectedImage {
  final File image;
  final double width;
  final double height;

  SelectedImage(
      {required this.image, required this.width, required this.height});
}

class SelectImage {
  Future<SelectedImage?> selectImage() async {
    final imagePicker = ImagePicker();
    final image = await imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) {
      return null;
    }
    final file = File(image.path);
    final decodedImage = await decodeImageFromList(file.readAsBytesSync());
    return SelectedImage(
        image: file,
        width: decodedImage.width.toDouble(),
        height: decodedImage.height.toDouble());
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Material App Bar'),
      ),
      body: FutureBuilder(
        future: SelectImage().selectImage(),
        builder:
            (BuildContext context, AsyncSnapshot<SelectedImage?> snapshot) {
          if (snapshot.hasData) {
            final selected = snapshot.data;
            if (selected == null) {
              return const Text('No image selected.');
            }
            return ProcessImage(selectedImage: selected);
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

class DetectedPose {
  final double x;
  final double y;
  final File image;

  DetectedPose({required this.x, required this.y, required this.image});

  @override
  String toString() {
    return 'DetectedPose{x: $x, y: $y, image: $image}';
  }
}

class PoseDetectorService {
  final PoseDetector detector;
  final BuildContext context;
  final SelectedImage selectedImage;

  PoseDetectorService(
      {required this.detector,
      required this.context,
      required this.selectedImage});

  factory PoseDetectorService.init(
      BuildContext context, SelectedImage selectedImage) {
    final detector = PoseDetector(options: PoseDetectorOptions());
    return PoseDetectorService(
        detector: detector, context: context, selectedImage: selectedImage);
  }

  double get scale {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final imageWidth = selectedImage.width;
    return screenWidth / imageWidth;
  }

  Future<DetectedPose> detectRightShoulder() async {
    final inputImage = InputImage.fromFilePath(selectedImage.image.path);
    final poses = await detector.processImage(inputImage);
    final rightShoulder = poses[0].landmarks[PoseLandmarkType.rightShoulder];
    if (rightShoulder != null) {
      return DetectedPose(
          x: rightShoulder.x * scale,
          y: rightShoulder.y * scale,
          image: selectedImage.image);
    }
    return DetectedPose(x: 0, y: 0, image: selectedImage.image);
  }
}

class ProcessImage extends StatefulWidget {
  final SelectedImage selectedImage;

  const ProcessImage({super.key, required this.selectedImage});

  @override
  State<ProcessImage> createState() => _ProcessImageState();
}

class _ProcessImageState extends State<ProcessImage> {
  final poseDetector = PoseDetector(options: PoseDetectorOptions());

  @override
  void dispose() {
    poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: PoseDetectorService.init(context, widget.selectedImage)
          .detectRightShoulder(),
      builder: (BuildContext context, AsyncSnapshot<DetectedPose> snapshot) {
        if (snapshot.hasData) {
          final detected = snapshot.data;

          if (detected == null) {
            return const Text('Right shoulder not detected.');
          }
          return Stack(
            children: [
              Image.file(detected.image),
              Positioned(
                left: detected.x + 20,
                top: detected.y + 26,
                child: const Icon(
                  Icons.touch_app_rounded,
                  color: Colors.white,
                  size: 50,
                ),
              )
            ],
          );
        }
        if (snapshot.hasError) {
          return Text(snapshot.error.toString());
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
