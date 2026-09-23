import 'package:vector_math/vector_math.dart';

/// Component representing a Kinematic Character Controller (KCC).
/// Interacts with the PhysicsServer to handle precise combat movements.
class KinematicControllerComponent {
  final int entityId;
  final int bodyId;

  Vector3 velocity = Vector3.zero();
  bool isGrounded = false;

  KinematicControllerComponent(this.entityId, this.bodyId);

  void move(Vector3 direction, double speed, double dt) {
    velocity = direction * speed;
    // In a full implementation, apply to PhysicsServer using setBodyLinearVelocity or similar.
  }

  void jump(double force) {
    if (isGrounded) {
      velocity.y += force;
      isGrounded = false;
    }
  }
}
