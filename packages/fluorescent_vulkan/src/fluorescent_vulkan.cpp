#include "fluorescent_vulkan.h"
#include <vulkan/vulkan.h>
#include <iostream>
#include <vector>
#include <cstring>
#include "shaders.h"

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

static VkShaderModule g_vertex_shader = VK_NULL_HANDLE;
static VkShaderModule g_fragment_shader = VK_NULL_HANDLE;
static VkDescriptorSetLayout g_descriptor_set_layout = VK_NULL_HANDLE;
static VkPipelineLayout g_pipeline_layout = VK_NULL_HANDLE;
static VkPipeline g_graphics_pipeline = VK_NULL_HANDLE;
static VkRenderPass g_render_pass = VK_NULL_HANDLE;
static VkCommandPool g_command_pool = VK_NULL_HANDLE;
static VkDescriptorPool g_descriptor_pool = VK_NULL_HANDLE;
static VkDescriptorSet g_descriptor_set = VK_NULL_HANDLE;

// UBO State
static VkBuffer g_uniform_buffer = VK_NULL_HANDLE;
static VkDeviceMemory g_uniform_buffer_memory = VK_NULL_HANDLE;
static void* g_uniform_buffer_mapped = nullptr;

static float g_view_proj_matrix[16] = {
    1.0f, 0.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f, 0.0f,
    0.0f, 0.0f, 1.0f, 0.0f,
    0.0f, 0.0f, 0.0f, 1.0f
};

uint32_t findMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties) {
    VkPhysicalDeviceMemoryProperties memProperties;
    vkGetPhysicalDeviceMemoryProperties(g_physical_device, &memProperties);

    for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
        if ((typeFilter & (1 << i)) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }
    ALOGE("failed to find suitable memory type!");
    return 0;
}

void createBuffer(VkDeviceSize size, VkBufferUsageFlags usage, VkMemoryPropertyFlags properties, VkBuffer& buffer, VkDeviceMemory& bufferMemory) {
    VkBufferCreateInfo bufferInfo{};
    bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufferInfo.size = size;
    bufferInfo.usage = usage;
    bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    if (vkCreateBuffer(g_device, &bufferInfo, nullptr, &buffer) != VK_SUCCESS) {
        ALOGE("failed to create buffer!");
    }

    VkMemoryRequirements memRequirements;
    vkGetBufferMemoryRequirements(g_device, buffer, &memRequirements);

    VkMemoryAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memRequirements.size;
    allocInfo.memoryTypeIndex = findMemoryType(memRequirements.memoryTypeBits, properties);

    if (vkAllocateMemory(g_device, &allocInfo, nullptr, &bufferMemory) != VK_SUCCESS) {
        ALOGE("failed to allocate buffer memory!");
    }

    vkBindBufferMemory(g_device, buffer, bufferMemory, 0);
}


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
    extensions.push_back(VK_KHR_EXTERNAL_MEMORY_CAPABILITIES_EXTENSION_NAME);
#endif

    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
    createInfo.ppEnabledExtensionNames = extensions.data();
    createInfo.enabledLayerCount = 0;

    if (vkCreateInstance(&createInfo, nullptr, &g_instance) != VK_SUCCESS) {
        ALOGE("Failed to create Vulkan instance!");
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

    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(g_instance, &deviceCount, nullptr);
    if (deviceCount == 0) {
        ALOGE("Failed to find GPUs with Vulkan support!");
        return false;
    }
    std::vector<VkPhysicalDevice> devices(deviceCount);
    vkEnumeratePhysicalDevices(g_instance, &deviceCount, devices.data());
    g_physical_device = devices[0];

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

    VkDeviceQueueCreateInfo queueCreateInfo{};
    queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueCreateInfo.queueFamilyIndex = graphicsQueueFamilyIndex;
    queueCreateInfo.queueCount = 1;
    float queuePriority = 1.0f;
    queueCreateInfo.pQueuePriorities = &queuePriority;

    VkPhysicalDeviceFeatures deviceFeatures{};

    std::vector<const char*> deviceExtensions;
#ifdef __ANDROID__
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

    if (vkCreateDevice(g_physical_device, &createInfo, nullptr, &g_device) != VK_SUCCESS) {
        ALOGE("Failed to create logical device!");
        return false;
    }
    vkGetDeviceQueue(g_device, graphicsQueueFamilyIndex, 0, &g_graphics_queue);

    VkCommandPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = graphicsQueueFamilyIndex;
    if (vkCreateCommandPool(g_device, &poolInfo, nullptr, &g_command_pool) != VK_SUCCESS) {
        ALOGE("Failed to create command pool!");
        return false;
    }

    ALOGI("Vulkan Logical Device and Graphics Queue created successfully.");
    return true;
}

VkShaderModule create_shader_module(const uint32_t* code, size_t size) {
    VkShaderModuleCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    createInfo.codeSize = size;
    createInfo.pCode = code;

    VkShaderModule shaderModule;
    if (vkCreateShaderModule(g_device, &createInfo, nullptr, &shaderModule) != VK_SUCCESS) {
        ALOGE("Failed to create shader module!");
        return VK_NULL_HANDLE;
    }
    return shaderModule;
}

bool init_graphics_pipeline() {
    if (g_device == VK_NULL_HANDLE) {
        ALOGE("Cannot initialize pipeline without Vulkan device.");
        return false;
    }

    // --- UBO SETUP ---
    VkDeviceSize bufferSize = sizeof(float) * 16;
    createBuffer(bufferSize, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, g_uniform_buffer, g_uniform_buffer_memory);
    vkMapMemory(g_device, g_uniform_buffer_memory, 0, bufferSize, 0, &g_uniform_buffer_mapped);
    memcpy(g_uniform_buffer_mapped, g_view_proj_matrix, bufferSize);

    // --- DESCRIPTOR SET LAYOUT ---
    VkDescriptorSetLayoutBinding uboLayoutBinding{};
    uboLayoutBinding.binding = 0;
    uboLayoutBinding.descriptorCount = 1;
    uboLayoutBinding.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    uboLayoutBinding.pImmutableSamplers = nullptr;
    uboLayoutBinding.stageFlags = VK_SHADER_STAGE_VERTEX_BIT;

    VkDescriptorSetLayoutCreateInfo layoutInfo{};
    layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layoutInfo.bindingCount = 1;
    layoutInfo.pBindings = &uboLayoutBinding;

    if (vkCreateDescriptorSetLayout(g_device, &layoutInfo, nullptr, &g_descriptor_set_layout) != VK_SUCCESS) {
        ALOGE("Failed to create descriptor set layout!");
        return false;
    }

    // --- DESCRIPTOR POOL ---
    VkDescriptorPoolSize poolSize{};
    poolSize.type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    poolSize.descriptorCount = 1;

    VkDescriptorPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    poolInfo.poolSizeCount = 1;
    poolInfo.pPoolSizes = &poolSize;
    poolInfo.maxSets = 1;

    if (vkCreateDescriptorPool(g_device, &poolInfo, nullptr, &g_descriptor_pool) != VK_SUCCESS) {
        ALOGE("Failed to create descriptor pool!");
        return false;
    }

    // --- DESCRIPTOR SETS ---
    VkDescriptorSetAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    allocInfo.descriptorPool = g_descriptor_pool;
    allocInfo.descriptorSetCount = 1;
    allocInfo.pSetLayouts = &g_descriptor_set_layout;

    if (vkAllocateDescriptorSets(g_device, &allocInfo, &g_descriptor_set) != VK_SUCCESS) {
        ALOGE("Failed to allocate descriptor sets!");
        return false;
    }

    VkDescriptorBufferInfo bufferInfo{};
    bufferInfo.buffer = g_uniform_buffer;
    bufferInfo.offset = 0;
    bufferInfo.range = sizeof(float) * 16;

    VkWriteDescriptorSet descriptorWrite{};
    descriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrite.dstSet = g_descriptor_set;
    descriptorWrite.dstBinding = 0;
    descriptorWrite.dstArrayElement = 0;
    descriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    descriptorWrite.descriptorCount = 1;
    descriptorWrite.pBufferInfo = &bufferInfo;

    vkUpdateDescriptorSets(g_device, 1, &descriptorWrite, 0, nullptr);

    // --- SHADER SETUP ---
    g_vertex_shader = create_shader_module(VERTEX_SHADER, sizeof(VERTEX_SHADER));
    g_fragment_shader = create_shader_module(FRAGMENT_SHADER, sizeof(FRAGMENT_SHADER));

    VkPipelineShaderStageCreateInfo vertShaderStageInfo{};
    vertShaderStageInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    vertShaderStageInfo.stage = VK_SHADER_STAGE_VERTEX_BIT;
    vertShaderStageInfo.module = g_vertex_shader;
    vertShaderStageInfo.pName = "main";

    VkPipelineShaderStageCreateInfo fragShaderStageInfo{};
    fragShaderStageInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    fragShaderStageInfo.stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    fragShaderStageInfo.module = g_fragment_shader;
    fragShaderStageInfo.pName = "main";

    VkPipelineShaderStageCreateInfo shaderStages[] = {vertShaderStageInfo, fragShaderStageInfo};

    VkPipelineVertexInputStateCreateInfo vertexInputInfo{};
    vertexInputInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    vertexInputInfo.vertexBindingDescriptionCount = 0;
    vertexInputInfo.pVertexBindingDescriptions = nullptr;
    vertexInputInfo.vertexAttributeDescriptionCount = 0;
    vertexInputInfo.pVertexAttributeDescriptions = nullptr;

    VkPipelineInputAssemblyStateCreateInfo inputAssembly{};
    inputAssembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    inputAssembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    inputAssembly.primitiveRestartEnable = VK_FALSE;

    // Viewport and scissor are usually dynamic state, but defining them statically here
    VkViewport viewport{};
    viewport.x = 0.0f;
    viewport.y = 0.0f;
    viewport.width = 100.0f;  // These will be overridden by dynamic state
    viewport.height = 100.0f; // if dynamic state is enabled, but we leave them hardcoded for now
    viewport.minDepth = 0.0f;
    viewport.maxDepth = 1.0f;

    VkRect2D scissor{};
    scissor.offset = {0, 0};
    scissor.extent = {100, 100};

    VkPipelineViewportStateCreateInfo viewportState{};
    viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewportState.viewportCount = 1;
    viewportState.pViewports = &viewport;
    viewportState.scissorCount = 1;
    viewportState.pScissors = &scissor;

    // Use dynamic states for viewport and scissor so we don't have to recreate the pipeline
    // every time the AHB resizes
    std::vector<VkDynamicState> dynamicStates = {
        VK_DYNAMIC_STATE_VIEWPORT,
        VK_DYNAMIC_STATE_SCISSOR
    };

    VkPipelineDynamicStateCreateInfo dynamicState{};
    dynamicState.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynamicState.dynamicStateCount = static_cast<uint32_t>(dynamicStates.size());
    dynamicState.pDynamicStates = dynamicStates.data();

    VkPipelineRasterizationStateCreateInfo rasterizer{};
    rasterizer.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rasterizer.depthClampEnable = VK_FALSE;
    rasterizer.rasterizerDiscardEnable = VK_FALSE;
    rasterizer.polygonMode = VK_POLYGON_MODE_FILL;
    rasterizer.lineWidth = 1.0f;
    rasterizer.cullMode = VK_CULL_MODE_NONE; // No culling for simple triangle
    rasterizer.frontFace = VK_FRONT_FACE_CLOCKWISE;

    VkPipelineMultisampleStateCreateInfo multisampling{};
    multisampling.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisampling.sampleShadingEnable = VK_FALSE;
    multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

    VkPipelineColorBlendAttachmentState colorBlendAttachment{};
    colorBlendAttachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    colorBlendAttachment.blendEnable = VK_FALSE;

    VkPipelineColorBlendStateCreateInfo colorBlending{};
    colorBlending.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    colorBlending.logicOpEnable = VK_FALSE;
    colorBlending.attachmentCount = 1;
    colorBlending.pAttachments = &colorBlendAttachment;

    VkPipelineLayoutCreateInfo pipelineLayoutInfo{};
    pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipelineLayoutInfo.setLayoutCount = 1;
    pipelineLayoutInfo.pSetLayouts = &g_descriptor_set_layout;

    if (vkCreatePipelineLayout(g_device, &pipelineLayoutInfo, nullptr, &g_pipeline_layout) != VK_SUCCESS) {
        ALOGE("Failed to create pipeline layout!");
        return false;
    }

    VkAttachmentDescription colorAttachment{};
    colorAttachment.format = VK_FORMAT_R8G8B8A8_UNORM;
    colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
    colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    colorAttachment.finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkAttachmentReference colorAttachmentRef{};
    colorAttachmentRef.attachment = 0;
    colorAttachmentRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkSubpassDescription subpass{};
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &colorAttachmentRef;

    VkRenderPassCreateInfo renderPassInfo{};
    renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    renderPassInfo.attachmentCount = 1;
    renderPassInfo.pAttachments = &colorAttachment;
    renderPassInfo.subpassCount = 1;
    renderPassInfo.pSubpasses = &subpass;

    if (vkCreateRenderPass(g_device, &renderPassInfo, nullptr, &g_render_pass) != VK_SUCCESS) {
        ALOGE("Failed to create render pass!");
        return false;
    }

    VkGraphicsPipelineCreateInfo pipelineInfo{};
    pipelineInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    pipelineInfo.stageCount = 2;
    pipelineInfo.pStages = shaderStages;
    pipelineInfo.pVertexInputState = &vertexInputInfo;
    pipelineInfo.pInputAssemblyState = &inputAssembly;
    pipelineInfo.pViewportState = &viewportState;
    pipelineInfo.pRasterizationState = &rasterizer;
    pipelineInfo.pMultisampleState = &multisampling;
    pipelineInfo.pColorBlendState = &colorBlending;
    pipelineInfo.pDynamicState = &dynamicState;
    pipelineInfo.layout = g_pipeline_layout;
    pipelineInfo.renderPass = g_render_pass;
    pipelineInfo.subpass = 0;
    pipelineInfo.basePipelineHandle = VK_NULL_HANDLE;

    if (vkCreateGraphicsPipelines(g_device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &g_graphics_pipeline) != VK_SUCCESS) {
        ALOGE("Failed to create graphics pipeline!");
        return false;
    }

    ALOGI("Vulkan Graphics Pipeline, Layout, and Render Pass initialized.");
    return true;
}

extern "C" void update_camera(const float* view_proj_matrix) {
    if (view_proj_matrix != nullptr) {
        for (int i = 0; i < 16; ++i) {
            g_view_proj_matrix[i] = view_proj_matrix[i];
        }
        if (g_uniform_buffer_mapped != nullptr) {
            memcpy(g_uniform_buffer_mapped, g_view_proj_matrix, sizeof(float) * 16);
        }
        ALOGI("Camera View-Projection Matrix updated and written to UBO.");
    }
}

void render_frame() {
    // This is currently left as a stub because vkCmdDraw needs to be wrapped in a render pass
    // targeting a specific VkFramebuffer. We moved the render_frame logic to vulkan_renderer.cpp
    // where it has access to the bound AHardwareBuffer and its associated Framebuffer.
}

void cleanup_vulkan() {
    if (g_device != VK_NULL_HANDLE) {
        vkDestroyPipeline(g_device, g_graphics_pipeline, nullptr);
        vkDestroyRenderPass(g_device, g_render_pass, nullptr);
        vkDestroyPipelineLayout(g_device, g_pipeline_layout, nullptr);
        vkDestroyShaderModule(g_device, g_fragment_shader, nullptr);
        vkDestroyShaderModule(g_device, g_vertex_shader, nullptr);
        vkDestroyDescriptorPool(g_device, g_descriptor_pool, nullptr);
        vkDestroyDescriptorSetLayout(g_device, g_descriptor_set_layout, nullptr);
        vkDestroyBuffer(g_device, g_uniform_buffer, nullptr);
        vkFreeMemory(g_device, g_uniform_buffer_memory, nullptr);
        vkDestroyCommandPool(g_device, g_command_pool, nullptr);
        vkDestroyDevice(g_device, nullptr);
        g_device = VK_NULL_HANDLE;
    }
    if (g_instance != VK_NULL_HANDLE) {
        vkDestroyInstance(g_instance, nullptr);
        g_instance = VK_NULL_HANDLE;
    }
    ALOGI("Fluorescent Vulkan: Cleaned up.");
}

VkDevice get_vulkan_device() { return g_device; }
VkPhysicalDevice get_vulkan_physical_device() { return g_physical_device; }
VkRenderPass get_vulkan_render_pass() { return g_render_pass; }
VkPipeline get_vulkan_graphics_pipeline() { return g_graphics_pipeline; }
VkPipelineLayout get_vulkan_pipeline_layout() { return g_pipeline_layout; }
VkCommandPool get_vulkan_command_pool() { return g_command_pool; }
VkQueue get_vulkan_graphics_queue() { return g_graphics_queue; }
VkDescriptorSet get_vulkan_descriptor_set() { return g_descriptor_set; }
