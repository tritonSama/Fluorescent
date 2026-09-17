/// Represents a lightweight entity identifier in the Entity Component System.
///
/// An [Entity] is an extension type over [int], providing zero-cost abstraction,
/// type safety, and direct interoperability with integer indices and lists.
extension type const Entity(int id) implements int {
  /// Sentinel value indicating an invalid or uninitialized entity.
  static const Entity invalid = Entity(-1);

  /// Whether this entity has a valid non-negative identifier.
  bool get isValid => id >= 0;
}
