/*
Project: Loam
File: vk/vk.jai
Author: Brock Salmon
Created: 11JUN2025
*/

FRAMES_IN_FLIGHT :: 2;

Vk :: struct {
    // Requested options
    instanceExtensions : [..] *u8;
    deviceExtensions : [..] *u8;
    
    reqFeatures_1_0 : VkPhysicalDeviceFeatures;
    reqFeatures_1_1 : VkPhysicalDeviceVulkan11Features;
    reqFeatures_1_2 : VkPhysicalDeviceVulkan12Features;
    reqFeatures_1_3 : VkPhysicalDeviceVulkan13Features;

    // Base Vulkan structs
    instance : VkInstance;
    surface : VkSurfaceKHR;
    physicalDevice : VkPhysicalDevice;
    device : VkDevice;
    swapchain : VkSwapchainKHR;

    swapchainImages : [..] VkImage;
    swapchainImageViews : [..] VkImageView;
    swapchainExtent : VkExtent2D;
    swapchainFormat : VkFormat;
    resizeRequested : bool;

    allocator : VmaAllocator;

    textureFormat : VkFormat;	

    currentFrame : u64;
    frames : [FRAMES_IN_FLIGHT] FrameCommandInfo;

    drawImage : *AllocatedImageInfo;
    
    graphicsQueue : VkQueue;

    QueueFamilyIndices :: struct {
	// NOTE: We don't store a transfer queue index, as graphics and compute queue families include the same capabilities
	graphics    : u32;
	compute     : u32;
	videoDecode : u32;
    }
    queueFamilyIndices : QueueFamilyIndices;

    // Immediate Submit
    immFence     : VkFence;
    immCmdBuffer : VkCommandBuffer;
    immCmdPool   : VkCommandPool;
    ///////////////////

    // Pipelines
    pipelines : [#run enum_highest_value(PipelineTypes) + 1] RenderingPipelineInfo;
    pipelineCache : VkPipelineCache;
    
    // Sampler for each member of VkFilter (we don't care about CUBIC)
    defaultSampler_Nearest : VkSampler;
    defaultSampler_Linear  : VkSampler;

    defaultPlaneIndexBuffer : *AllocatedBufferInfo;
    
    // Built in error texture
    errorCheckerboard : *AllocatedImageInfo;

    descriptorAllocator : DynamicDescriptorPoolAllocator;

    imagesToDestroyAtFrameReset : [..] *AllocatedImageInfo;
    buffersToDestroyAtFrameReset : [..] *AllocatedBufferInfo;

    // Optional Stuff
    enableVkVideo : bool;

    // Settings
    vsync := false;
    /////////////
}

FrameCommandInfo :: struct {
    cmdPool : VkCommandPool;
    cmdBuffer : VkCommandBuffer;
    
    swapSemaphore : VkSemaphore;
    renderSemaphore : VkSemaphore;
    renderFence : VkFence;
}

AllocatedImageInfo :: struct {
    image  : VkImage;
    view   : VkImageView;
    extent : VkExtent2D;
    format : VkFormat;

    allocation : VmaAllocation;
}

AllocatedBufferInfo :: struct {
    buffer         : VkBuffer;
    allocation     : VmaAllocation;
    allocationInfo : VmaAllocationInfo;
}

AllPushConstants :: struct {
    renderMatrix : Matrix4;
    colourTint   : Vector4;
    
    vertexBuffer : VkDeviceAddress;
}

#load "descriptors.jai";
#load "init.jai";
#load "mesh.jai";
#load "pipelines.jai";
#load "render.jai";
#load "render_commands.jai";
#load "shaders.jai";
#load "sprite.jai";
#load "text.jai";
#load "ui.jai";
#load "util.jai";
