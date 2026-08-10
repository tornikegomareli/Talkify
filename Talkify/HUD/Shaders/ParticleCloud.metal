#include <metal_stdlib>
using namespace metal;

/// The Edge Glow particle cloud, drawn by a compute pipeline into the
/// MTKView's drawable (HUDParticleCloudView): silver motes respawn at random
/// positions, drift toward the glow origin under the notch housing, and are
/// consumed there. Cloud-wide `progress` (the session ramp) scales every
/// particle's alpha and radius, so the cloud fades and shrinks away together.
///
/// These structs are mirrored member-for-member in Swift (ParticleRenderer);
/// HUDParticleLayoutTests pins the shared layout — reordering members here
/// breaks the buffer silently.

struct Particle {
  float4 color;
  float radius;
  float lifespan;
  float2 position;
  float2 velocity;
};

struct ParticleCloudInfo {
  float2 center;     // normalized 0…1
  float progress;    // session ramp, 0…1
};

// Cheap 2D hash → 0…1. Inline so there is no third-party RNG dependency.
static float rand(float2 seed) {
  return fract(sin(dot(seed, float2(12.9898, 78.233))) * 43758.5453);
}

kernel void cleanScreen(
  texture2d<half, access::write> output [[ texture(0) ]],
  uint2 id [[ thread_position_in_grid ]]
) {
  if (id.x >= output.get_width() || id.y >= output.get_height()) {
    return;
  }
  output.write(half4(0), id);
}

kernel void drawParticles(
  texture2d<half, access::write> output [[ texture(0) ]],
  device Particle *particles [[ buffer(0) ]],
  constant ParticleCloudInfo &info [[ buffer(1) ]],
  uint id [[ thread_position_in_grid ]]
) {
  float width = output.get_width();
  float height = output.get_height();
  float2 center = float2(width * info.center.x, height * info.center.y);

  Particle particle = particles[id];
  float lifespan = particle.lifespan;
  float2 position = particle.position;

  if (length(center - position) < 12.0 ||
    (position.x == 0.0 && position.y == 0.0) ||
    lifespan > 100.0) {
    // Respawn somewhere new; the old position feeds the hash so a
    // particle never loops through the same spot twice.
    float2 seed = position + float2(id, lifespan);
    position = float2(rand(seed) * width, rand(seed.yx + 1.37) * height);
    lifespan = 0.0;
  } else {
    float2 direction = normalize(center - position);
    position += direction * length(particle.velocity);
    lifespan += 1.0;
  }

  particle.lifespan = lifespan;
  particle.position = position;
  particles[id] = particle;

  // Young particles fade in over their life; the session ramp scales the
  // whole cloud.
  half4 color = half4(particle.color)
    * half(min(lifespan / 100.0, 1.0))
    * half(info.progress);
  int radius = int(particle.radius * info.progress);
  int2 origin = int2(position);
  int2 bounds = int2(width, height);

  for (int y = -radius; y <= radius; y++) {
    for (int x = -radius; x <= radius; x++) {
      if (x * x + y * y > radius * radius) {
        continue;
      }
      int2 pixel = origin + int2(x, y);
      if (pixel.x >= 0 && pixel.y >= 0
        && pixel.x < bounds.x && pixel.y < bounds.y) {
        output.write(color, uint2(pixel));
      }
    }
  }
}
