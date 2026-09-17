import 'dart:async';

/// Base abstract class for low-level Fluorescent servers
/// (e.g., RenderingServer, PhysicsServer, NavigationServer).
///
/// Fluorescent follows Godot's server-based architecture where heavyweight
/// simulation and graphics subsystems are decoupled behind abstract server APIs
/// that operate on opaque handle IDs and can run concurrently in background Isolates.
abstract class Server {
  /// Whether this server has been initialized and is ready to process commands.
  bool get isInitialized;

  /// Initializes the server subsystem and internal resources.
  Future<void> initialize();

  /// Advances the server state by [dt] seconds.
  void step(double dt);

  /// Disposes resources held by this server.
  Future<void> dispose();
}
