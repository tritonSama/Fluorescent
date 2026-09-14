#ifndef FLUORESCENT_VULKAN_H
#define FLUORESCENT_VULKAN_H

#include <stdint.h>
#include <stdbool.h>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Initialize the Vulkan engine. Returns true on success.
EXPORT bool init_vulkan();

// Initialize the Vulkan device. Returns true on success.
EXPORT bool init_vulkan_device();

// Renders a frame.
EXPORT void render_frame();

// Clean up resources.
EXPORT void cleanup_vulkan();

#ifdef __cplusplus
}
#endif

#endif // FLUORESCENT_VULKAN_H
