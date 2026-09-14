#include "fluorescent_vulkan.h"
#include <vulkan/vulkan.h>
#include <iostream>
#include <vector>

#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "FluorescentVulkanCore"
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define ALOGI(...) std::cout << "FluorescentVulkanCore: " << __VA_ARGS__ << std::endl
#define ALOGE(...) std::cerr << "FluorescentVulkanCore ERROR: " << __VA_ARGS__ << std::endl
#endif

// Global Vulkan state for this simplistic implementation
static VkInstance g_instance = VK_NULL_HANDLE;
static VkPhysicalDevice g_physical_device = VK_NULL_HANDLE;
static VkDevice g_device = VK_NULL_HANDLE;
static VkQueue g_graphics_queue = VK_NULL_HANDLE;

bool init_vulkan() {
    if (g_instance != VK_NULL_HANDLE) {
        return true;
    }

    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "Fluorescent Engine";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.pEngineName = "Fluorescent";
    appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_1;

    std::vector<const char*> extensions;
    extensions.push_back(VK_KHR_SURFACE_EXTENSION_NAME);
#ifdef __ANDROID__
    extensions.push_back("VK_KHR_android_surface");
    // We need external memory capabilities to bind Android Hardware Buffers
    extensions.push_back(VK_KHR_EXTERNAL_MEMORY_CAPABILITIES_EXTENSION_NAME);
#endif

    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
    createInfo.ppEnabledExtensionNames = extensions.data();
    createInfo.enabledLayerCount = 0;

    VkResult result = vkCreateInstance(&createInfo, nullptr, &g_instance);
    if (result != VK_SUCCESS) {
        ALOGE("Failed to create Vulkan instance! Error code: %d", result);
        return false;
    }

    ALOGI("Vulkan Instance created successfully.");
    return true;
}

bool init_vulkan_device() {
    if (g_instance == VK_NULL_HANDLE) {
        ALOGE("Cannot initialize device without Vulkan instance.");
        return false;
    }

    // Physical Device Selection
    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(g_instance, &deviceCount, nullptr);

    if (deviceCount == 0) {
        ALOGE("Failed to find GPUs with Vulkan support!");
        return false;
    }

    std::vector<VkPhysicalDevice> devices(deviceCount);
    vkEnumeratePhysicalDevices(g_instance, &deviceCount, devices.data());

    g_physical_device = devices[0]; // Simple selection (first available)

    // Queue Family Selection
    uint32_t queueFamilyCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(g_physical_device, &queueFamilyCount, nullptr);

    std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
    vkGetPhysicalDeviceQueueFamilyProperties(g_physical_device, &queueFamilyCount, queueFamilies.data());

    int graphicsQueueFamilyIndex = -1;
    for (uint32_t i = 0; i < queueFamilyCount; ++i) {
        if (queueFamilies[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
            graphicsQueueFamilyIndex = i;
            break;
        }
    }

    if (graphicsQueueFamilyIndex == -1) {
        ALOGE("Failed to find a suitable queue family!");
        return false;
    }

    // Logical Device Creation
    VkDeviceQueueCreateInfo queueCreateInfo{};
    queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueCreateInfo.queueFamilyIndex = graphicsQueueFamilyIndex;
    queueCreateInfo.queueCount = 1;
    float queuePriority = 1.0f;
    queueCreateInfo.pQueuePriorities = &queuePriority;

    VkPhysicalDeviceFeatures deviceFeatures{};

    std::vector<const char*> deviceExtensions;
#ifdef __ANDROID__
    // Required to interact with Android Hardware Buffers
    deviceExtensions.push_back("VK_ANDROID_external_memory_android_hardware_buffer");
    deviceExtensions.push_back(VK_KHR_SAMPLER_YCBCR_CONVERSION_EXTENSION_NAME);
    deviceExtensions.push_back(VK_KHR_EXTERNAL_MEMORY_EXTENSION_NAME);
    deviceExtensions.push_back(VK_EXT_QUEUE_FAMILY_FOREIGN_EXTENSION_NAME);
    deviceExtensions.push_back(VK_KHR_DEDICATED_ALLOCATION_EXTENSION_NAME);
    deviceExtensions.push_back(VK_KHR_GET_MEMORY_REQUIREMENTS_2_EXTENSION_NAME);
    deviceExtensions.push_back(VK_KHR_BIND_MEMORY_2_EXTENSION_NAME);
#endif

    VkDeviceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    createInfo.pQueueCreateInfos = &queueCreateInfo;
    createInfo.queueCreateInfoCount = 1;
    createInfo.pEnabledFeatures = &deviceFeatures;
    createInfo.enabledExtensionCount = static_cast<uint32_t>(deviceExtensions.size());
    createInfo.ppEnabledExtensionNames = deviceExtensions.data();

    VkResult result = vkCreateDevice(g_physical_device, &createInfo, nullptr, &g_device);
    if (result != VK_SUCCESS) {
        ALOGE("Failed to create logical device! Error code: %d", result);
        return false;
    }

    vkGetDeviceQueue(g_device, graphicsQueueFamilyIndex, 0, &g_graphics_queue);

    ALOGI("Vulkan Logical Device and Graphics Queue created successfully.");
    return true;
}

void render_frame() {
    // Basic stub demonstrating where the render command buffer recording would go
    if (g_device == VK_NULL_HANDLE) return;
    // ... record commands to render a triangle ...
    // ... submit to g_graphics_queue ...
    ALOGI("Render frame executed.");
}

void cleanup_vulkan() {
    if (g_device != VK_NULL_HANDLE) {
        vkDestroyDevice(g_device, nullptr);
        g_device = VK_NULL_HANDLE;
    }
    if (g_instance != VK_NULL_HANDLE) {
        vkDestroyInstance(g_instance, nullptr);
        g_instance = VK_NULL_HANDLE;
    }
    ALOGI("Fluorescent Vulkan: Cleaned up.");
}

VkDevice get_vulkan_device() {
    return g_device;
}

VkPhysicalDevice get_vulkan_physical_device() {
    return g_physical_device;
}

bool init_graphics_pipeline() {
    if (g_device == VK_NULL_HANDLE) {
        ALOGE("Cannot initialize pipeline without Vulkan device.");
        return false;
    }
    // In a real implementation: load shaders, create layout, renderpass, and pipeline object
    // Here we'd compile simple hardcoded triangle shaders.
    ALOGI("Vulkan Graphics Pipeline initialized (stub).");
    return true;
}
