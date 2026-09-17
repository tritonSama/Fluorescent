import 'component.dart';

/// Inspired by O3DE's Entity-Component-System pattern.
/// Represents a generic 3D object in the world.
class Entity3D {
  final String id;
  final List<Component3D> _components = [];

  Entity3D(this.id);

  void addComponent(Component3D component) {
    _components.add(component);
    component.onAddedToEntity(this);
  }

  T? getComponent<T extends Component3D>() {
    for (var c in _components) {
      if (c is T) return c;
    }
    return null;
  }
}
