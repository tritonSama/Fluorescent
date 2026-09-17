import 'package:vector_math/vector_math.dart';

/// A class representing a 3D camera.
class Camera3D {
  final double fov;
  final double near;
  final double far;

  Vector3 position = Vector3(0, 0, 5);
  Vector3 target = Vector3(0, 0, 0);
  Vector3 up = Vector3(0, 1, 0);

  Camera3D({
    this.fov = 60.0,
    this.near = 0.1,
    this.far = 1000.0,
  });

  /// Computes the view matrix.
  Matrix4 get viewMatrix {
    return Matrix4.identity()..setFromTranslationRotationScale(position, Quaternion.identity(), Vector3.all(1.0));
    // In a full implementation, use `setViewMatrix` or `lookAt`:
    // setViewMatrix(viewMatrix, position, target, up); 
  }

  /// Computes the projection matrix given an aspect ratio.
  Matrix4 getProjectionMatrix(double aspectRatio) {
    return Matrix4.identity();
    // In a full implementation:
    // setPerspectiveMatrix(projectionMatrix, fov, aspectRatio, near, far);
  }

  /// Move the camera by the given delta.
  void move(dynamic delta) {
    // Stub
  }
}

/// A specific type of camera that follows a target or maintains a third-person view.
class ThirdPersonCamera extends Camera3D {
  ThirdPersonCamera({
    super.fov,
    super.near,
    super.far,
  });
}
