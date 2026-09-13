/// A stub class representing a 3D camera.
class Camera3D {
  final double fov;
  final double near;
  final double far;

  Camera3D({
    this.fov = 60.0,
    this.near = 0.1,
    this.far = 1000.0,
  });

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
