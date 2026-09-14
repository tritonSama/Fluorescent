#include <jni.h>
#include <android/hardware_buffer_jni.h>
#include <android/log.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>
#include "../../src/fluorescent_vulkan.h"
#include "../../src/model_loader.h"

#define LOG_TAG "FluorescentVulkanAndroid"
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Global to hold the Vulkan Image bound to the AHB
static VkImage g_ahb_image = VK_NULL_HANDLE;
static VkDeviceMemory g_ahb_memory = VK_NULL_HANDLE;

// Binds the AHardwareBuffer to a Vulkan Image so we can render into it
void bind_hardware_buffer_to_vulkan(AHardwareBuffer* buffer) {
    VkDevice device = get_vulkan_device();
    if (device == VK_NULL_HANDLE) {
        ALOGE("Cannot bind buffer: Vulkan device is not initialized.");
        return;
    }

    AHardwareBuffer_Desc desc;
    AHardwareBuffer_describe(buffer, &desc);

    // Provide the Android hardware buffer properties
    VkAndroidHardwareBufferPropertiesANDROID ahbProperties{};
    ahbProperties.sType = VK_STRUCTURE_TYPE_ANDROID_HARDWARE_BUFFER_PROPERTIES_ANDROID;

    auto vkGetAndroidHardwareBufferPropertiesANDROID =
         (PFN_vkGetAndroidHardwareBufferPropertiesANDROID)vkGetDeviceProcAddr(device, "vkGetAndroidHardwareBufferPropertiesANDROID");

    if (vkGetAndroidHardwareBufferPropertiesANDROID != nullptr) {
         if (vkGetAndroidHardwareBufferPropertiesANDROID(device, buffer, &ahbProperties) != VK_SUCCESS) {
             ALOGE("Failed to get AHardwareBuffer properties.");
             return;
         }
    } else {
         ALOGE("vkGetAndroidHardwareBufferPropertiesANDROID not found.");
         return;
    }

    // Provide external memory info pointing to the hardware buffer
    VkExternalMemoryImageCreateInfo externalInfo{};
    externalInfo.sType = VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO;
    externalInfo.handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_ANDROID_HARDWARE_BUFFER_BIT_ANDROID;

    VkImageCreateInfo imageInfo{};
    imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imageInfo.pNext = &externalInfo;
    imageInfo.imageType = VK_IMAGE_TYPE_2D;
    imageInfo.format = VK_FORMAT_R8G8B8A8_UNORM;
    imageInfo.extent.width = desc.width;
    imageInfo.extent.height = desc.height;
    imageInfo.extent.depth = 1;
    imageInfo.mipLevels = 1;
    imageInfo.arrayLayers = 1;
    imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
    imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
    imageInfo.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    if (vkCreateImage(device, &imageInfo, nullptr, &g_ahb_image) != VK_SUCCESS) {
        ALOGE("Failed to create Vulkan Image from AHardwareBuffer.");
        return;
    }

    VkImportAndroidHardwareBufferInfoANDROID importInfo{};
    importInfo.sType = VK_STRUCTURE_TYPE_IMPORT_ANDROID_HARDWARE_BUFFER_INFO_ANDROID;
    importInfo.buffer = buffer;

    VkMemoryAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.pNext = &importInfo;
    allocInfo.allocationSize = ahbProperties.allocationSize;
    allocInfo.memoryTypeIndex = ahbProperties.memoryTypeBits; // Simplified lookup

    if (vkAllocateMemory(device, &allocInfo, nullptr, &g_ahb_memory) != VK_SUCCESS) {
        ALOGE("Failed to allocate memory for AHardwareBuffer Image.");
        return;
    }

    vkBindImageMemory(device, g_ahb_image, g_ahb_memory, 0);

    ALOGI("HardwareBuffer bound successfully to Vulkan Image. Width: %d, Height: %d", desc.width, desc.height);
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_fluorescent_vulkan_FluorescentVulkanPlugin_createHardwareBuffer(JNIEnv *env, jobject thiz, jint width, jint height) {
    if (!init_vulkan() || !init_vulkan_device()) {
        ALOGE("Failed to initialize Vulkan core from Android.");
        return 0;
    }

    init_graphics_pipeline();

    AHardwareBuffer_Desc desc = {};
    desc.width = width;
    desc.height = height;
    desc.layers = 1;
    desc.format = AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM;
    desc.usage = AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE | AHARDWAREBUFFER_USAGE_GPU_COLOR_OUTPUT;

    AHardwareBuffer *buffer = nullptr;
    int result = AHardwareBuffer_allocate(&desc, &buffer);
    if (result != 0) {
        ALOGE("Failed to allocate AHardwareBuffer.");
        return 0;
    }

    bind_hardware_buffer_to_vulkan(buffer);

    // Call render_frame to demonstrate doing work into the buffer
    render_frame();

    return reinterpret_cast<jlong>(buffer);
}

extern "C" JNIEXPORT void JNICALL
Java_com_fluorescent_vulkan_FluorescentVulkanPlugin_destroyHardwareBuffer(JNIEnv *env, jobject thiz, jlong bufferPtr) {
    if (g_ahb_image != VK_NULL_HANDLE) {
        vkDestroyImage(get_vulkan_device(), g_ahb_image, nullptr);
        g_ahb_image = VK_NULL_HANDLE;
    }
    if (g_ahb_memory != VK_NULL_HANDLE) {
        vkFreeMemory(get_vulkan_device(), g_ahb_memory, nullptr);
        g_ahb_memory = VK_NULL_HANDLE;
    }

    if (bufferPtr != 0) {
        AHardwareBuffer *buffer = reinterpret_cast<AHardwareBuffer *>(bufferPtr);
        AHardwareBuffer_release(buffer);
        ALOGI("AHardwareBuffer released.");
    }
}
