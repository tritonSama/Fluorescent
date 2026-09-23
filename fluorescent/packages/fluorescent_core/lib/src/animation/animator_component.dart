/// Represents an animation state machine for combat stances and actions.
class AnimatorComponent {
  final int entityId;
  String currentAnimation = "idle";
  double playbackSpeed = 1.0;
  bool loop = true;

  AnimatorComponent(this.entityId);

  /// Triggers a specific animation state.
  void play(String animationName, {double transitionDuration = 0.2}) {
    // Stub: Blend to the new animation using the state machine.
    currentAnimation = animationName;
  }

  /// Updates the animation state.
  void update(double dt) {
    // Advance animation time and update bone matrices.
  }
}
