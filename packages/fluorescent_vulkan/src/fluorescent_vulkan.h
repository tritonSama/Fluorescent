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

// Stubs the graphics pipeline creation
EXPORT bool init_graphics_pipeline();

// Renders a frame.
EXPORT void render_frame();

// Clean up resources.
EXPORT void cleanup_vulkan();

#ifdef __cplusplus
}
#endif

// Provides access to the Vulkan Device for Android specific extensions (like AHardwareBuffer)
#ifdef __cplusplus
#include <vulkan/vulkan.h>
VkDevice get_vulkan_device();
VkPhysicalDevice get_vulkan_physical_device();
#endif

#endif // FLUORESCENT_VULKAN_H
