# Strategic Vision

The core strategic vision for Fluorescent is a **Unified Application/Game Runtime**.

```text
                    YOUR ENGINE
                         │
             ┌───────────┴───────────┐
             │                       │
          Flutter                  Rust
             │                       │
       Application UI          Game Runtime
             │                       │
             └───────────┬───────────┘
                         │
                    3D Renderer
                         │
              ┌──────────┴──────────┐
              │                     │
           Android               Desktop
              │                     │
           Vulkan                Vulkan
```

The goal is a scalable engine where developers can build the game, launcher, UI, social systems, inventory, marketplace, settings, and editor tooling within a single cohesive environment. We embrace O3DE's baseline for networking, terrain, and asset processing to allow us to focus heavily on modern rendering techniques, an intuitive editor (built in Flutter), and deep multiplayer integration.

## AAA Renderer Scalability (Dynamic Tiers)

Don't blindly reproduce Nanite/Lumen. Build a scalable renderer:

```text
             SAME GAME
                 │
       ┌─────────┴─────────┐
       │                   │
   Android GPU         Desktop GPU
       │                   │
    Tier 1               Tier 4
       │                   │
   simplified          AAA renderer
```

The engine automatically determines what the hardware can support. That could become one of your differentiators.

## World Partition / Massive Worlds

Your engine should eventually have:

```text
World
│
├── World coordinates
├── Streaming cells
├── Level of detail
├── Entity streaming
├── Terrain streaming
├── Asset streaming
├── Physics streaming
├── AI streaming
└── Network relevance
```

And ideally:

```text
                 WORLD
                   │
        ┌──────────┼──────────┐
        │          │          │
      Cell A     Cell B     Cell C
        │          │          │
      Loaded     Loaded    Unloaded
```

O3DE already has large-world terrain and asset streaming concepts, so you wouldn't be starting from zero.

## Niagara-level VFX

This is a major system. You want:

```text
VFX Graph

Particle
  │
  ├── Position
  ├── Velocity
  ├── Rotation
  ├── Scale
  ├── Color
  ├── Collision
  ├── Forces
  ├── Noise
  ├── GPU simulation
  └── Events
```

And then: Fire, Smoke, Explosion, Magic, Rain, Snow, Dust, Sparks, Destruction, Weather, all built from the same underlying system.

## Advanced Animation

For AAA, you need considerably more than skeletal animation playback.

```text
Animation System
│
├── Animation Graph
├── State Machines
├── Blend Trees
├── IK
├── Full Body IK
├── Motion Matching
├── Retargeting
├── Procedural Animation
├── Facial Animation
├── Cloth
├── Ragdolls
└── Animation Compression
```

O3DE already has an Animation Editor and animation graphs, which gives you another useful starting point.

## Procedural Content Generation (PCG)

This is becoming extremely important. I'd make your version:

```text
PCG GRAPH

Input
 │
 ├── Terrain
 ├── Biome
 ├── Density
 ├── Slope
 ├── Height
 └── Noise
       │
       ▼
 Distribution
       │
 ┌─────┼─────┐
 │     │     │
Trees Rocks Buildings
 │     │     │
 └─────┴─────┘
       │
       ▼
 Generated World
```

That becomes particularly powerful when combined with your world-streaming system.

## Multiplayer Infrastructure

This should be treated as a first-class engine subsystem, not an add-on.

```text
Rust Networking

├── Client
├── Server
├── Replication
├── Prediction
├── Interpolation
├── Lag compensation
├── Rollback
├── Interest management
├── Entity ownership
├── Authentication
├── Matchmaking
└── Dedicated server
```

Rust is particularly attractive here.
