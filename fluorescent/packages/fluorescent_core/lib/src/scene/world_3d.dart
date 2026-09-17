import 'dart:io';
import 'entity.dart';
import 'fworld_loader.dart';

/// A class representing a 3D world containing meshes, lights, entities, and shaders.
class World3D {
  final String name;
  final Map<String, dynamic> metadata;
  final List<Entity3D> entities;
  final List<FWorldMesh> meshes;
  final List<FWorldShader> shaders;

  World3D({
    this.name = 'Default World',
    this.metadata = const {},
    this.entities = const [],
    this.meshes = const [],
    this.shaders = const [],
  });

  /// Loads a world from the given asset path.
  /// Automatically parses `.fworld` binary packages when available.
  static Future<World3D> load(String path) async {
    if (path.endsWith('.fworld')) {
      final file = File(path);
      if (await file.exists()) {
        return FWorldLoader.loadWorld(path);
      }
    }
    // Fallback stub: Simulate async loading
    await Future.delayed(const Duration(milliseconds: 100));
    return World3D(name: path);
  }
}
