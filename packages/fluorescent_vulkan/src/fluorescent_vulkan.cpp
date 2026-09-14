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

    VkDeviceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    createInfo.pQueueCreateInfos = &queueCreateInfo;
    createInfo.queueCreateInfoCount = 1;
    createInfo.pEnabledFeatures = &deviceFeatures;
    createInfo.enabledExtensionCount = 0;

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
    // Stub implementation for rendering a frame
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
