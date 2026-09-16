import 'entity.dart';

/// Base class for all 3D components attached to an Entity3D.
abstract class Component3D {
  Entity3D? entity;

  void onAddedToEntity(Entity3D entity) {
    this.entity = entity;
  }

  void update(double dt) {}
}
