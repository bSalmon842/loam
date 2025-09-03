/*
Project: Loam
File: vk/vk.jai
Author: Brock Salmon
Created: 11JUN2025
*/

FRAMES_IN_FLIGHT :: 2;
ERROR_TEXTURE_NAME :: "error_texture";

MAX_UPDATE_COMMANDS :: U16_MAX;
Vk :: struct {
    // Requested options
    instanceExtensions : [..] *u8;
    deviceExtensions : [..] *u8;
    
    reqFeatures_1_0     : VkPhysicalDeviceFeatures;
    reqFeatures_1_1     : VkPhysicalDeviceVulkan11Features;
    reqFeatures_1_2     : VkPhysicalDeviceVulkan12Features;
    reqFeatures_1_3     : VkPhysicalDeviceVulkan13Features;
    
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

    currentFrameIndex : u64;
    frames : [FRAMES_IN_FLIGHT] FrameCommandInfo;
    currentFrame : *FrameCommandInfo;

    drawImage : *AllocatedImageInfo;
    
    graphicsQueue : VkQueue;

    QueueFamilyIndices :: struct {
	// NOTE: We don't store a transfer queue index, as graphics and compute queue families include the same capabilities
	graphics    : u32;
	compute     : u32;
	videoDecode : u32;
    }
    queueFamilyIndices : QueueFamilyIndices;
    queueCountsPerFamily : QueueFamilyIndices;

    //descriptorAllocator : DynamicDescriptorPoolAllocator;

    bindlessDescriptorPool   : VkDescriptorPool;
    bindlessDescriptorSet    : VkDescriptorSet;
    bindlessDescriptorLayout : VkDescriptorSetLayout;
    bindlessTextureUpdates   : [..] *ImageResource;
    
    // Update Commands
    updateCmdPool  : VkCommandPool;
    updateCommands : [MAX_UPDATE_COMMANDS] *UpdateCommand;
    ///////////////////

    // Pipelines
    pipelines : [#run enum_highest_value(PipelineType) + 1] RenderingPipelineInfo;
    pipelineCache : VkPipelineCache;
    
    // Sampler for each member of VkFilter (we don't care about CUBIC)
    defaultSampler_Nearest : VkSampler;
    defaultSampler_Linear  : VkSampler;

    defaultPlaneIndexBuffer : *AllocatedBufferInfo;
    
    // Built in error texture
    errorCheckerboard : *AllocatedImageInfo;
    
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

SpritePushConstants :: struct {
    viewProj : Matrix4;
    spriteBuffer : VkDeviceAddress;
}

MeshPushConstants :: struct {
    renderMatrix : Matrix4;
    colourTint   : Vector4;
    textureID    : u32;
    vertexBuffer : VkDeviceAddress;
}

init_vk :: (window : Window_Type) {
    context.vk = loam.vk;
    vk = context.vk;
    
    check_vk(create_vk_instance("Test App"), "create_vk_instance failed: ");
    check_vk(create_vk_surface(window), "create_vk_surface failed: ");
    check_vk(get_vk_physical_device(), "get_vk_physical_device failed: ");
    check_vk(create_vk_device(), "create_vk_devices failed: ");

    allocatorCreateInfo := VmaAllocatorCreateInfo.{ .BUFFER_DEVICE_ADDRESS_BIT, vk.physicalDevice, vk.device, 0, null, null, null, null, vk.instance, VK_API_VERSION_1_3, null };
    check_vk(vmaCreateAllocator(*allocatorCreateInfo, *vk.allocator), "Failed to create VMA Allocator: ");
    
    check_vk(create_vk_swapchain(), "create_vk_swapchain failed: ");
    
    vkGetDeviceQueue(vk.device, vk.queueFamilyIndices.graphics, 0, *vk.graphicsQueue);
    
    select_texture_format();

    cmdPoolCreateInfo := VkCommandPoolCreateInfo.{.COMMAND_POOL_CREATE_INFO, null, .RESET_COMMAND_BUFFER_BIT, vk.queueFamilyIndices.graphics};
    fenceCreateInfo := VkFenceCreateInfo.{ .FENCE_CREATE_INFO, null, .SIGNALED_BIT };
    semaphoreCreateInfo := VkSemaphoreCreateInfo.{};
    
    for * vk.frames {
	check_vk(vkCreateCommandPool(vk.device, *cmdPoolCreateInfo, null, *it.cmdPool), tprint("Failed to create Command Pool for Frame %", it_index));
	
	cmdBufferAllocInfo := VkCommandBufferAllocateInfo.{ .COMMAND_BUFFER_ALLOCATE_INFO, null, it.cmdPool, .PRIMARY, 1 };
	check_vk(vkAllocateCommandBuffers(vk.device, *cmdBufferAllocInfo, *it.cmdBuffer), tprint("Failed to create Command Buffer for Frame %", it_index));
	
	check_vk(vkCreateSemaphore(vk.device, *semaphoreCreateInfo, null, *it.swapSemaphore), tprint("Failed to create Swap Semaphore for Frame %", it_index));
	check_vk(vkCreateSemaphore(vk.device, *semaphoreCreateInfo, null, *it.renderSemaphore), tprint("Failed to create Render Semaphore for Frame %", it_index));
	check_vk(vkCreateFence(vk.device, *fenceCreateInfo, null, *it.renderFence), tprint("Failed to create Render Fence for Frame %", it_index));
    }
    
    // Update Commands
    check_vk(vkCreateCommandPool(vk.device, *cmdPoolCreateInfo, null, *vk.updateCmdPool), "Failed to create Command Pool for Update Commands");

    // Samplers
    props : VkPhysicalDeviceProperties;
    vkGetPhysicalDeviceProperties(vk.physicalDevice, *props);
    maxSamplerAnisotropy := props.limits.maxSamplerAnisotropy;

    samplerCreateInfo : VkSamplerCreateInfo;

    samplerCreateInfo.minFilter = .NEAREST;
    samplerCreateInfo.magFilter = .NEAREST;
    vkCreateSampler(vk.device, *samplerCreateInfo, null, *vk.defaultSampler_Nearest);

    samplerCreateInfo.minFilter = .LINEAR;
    samplerCreateInfo.magFilter = .LINEAR;
    samplerCreateInfo.mipmapMode = .LINEAR;
    samplerCreateInfo.anisotropyEnable = VK_TRUE;
    samplerCreateInfo.maxAnisotropy = maxSamplerAnisotropy;
    vkCreateSampler(vk.device, *samplerCreateInfo, null, *vk.defaultSampler_Linear);

    // Bindless Descriptors
    vk.bindlessDescriptorPool = create_bindless_descriptor_pool();
    vk.bindlessDescriptorSet  = create_bindless_descriptor_set();
    
    // Pipelines
    init_pipelines();

    // Default Engine values
    vk.defaultPlaneIndexBuffer = create_vk_buffer(cast(u64) (DEFAULT_PLANE_INDICES.count * size_of(u32)), .INDEX_BUFFER_BIT | .TRANSFER_DST_BIT);
    memcpy(vk.defaultPlaneIndexBuffer.allocationInfo.pMappedData, cast(*u8) DEFAULT_PLANE_INDICES.data, size_of(u32) * DEFAULT_PLANE_INDICES.count);

    // Write error checkerboard texture
    pixels : [256] u32;
    for * pixels {
        it.* = cast(u32) ifx (it_index % 2 == (ifx it_index % 32 >= 16 then 1 else 0)) then 0xFFFF00FF else 0xFF000000;
    }
    
    vk.errorCheckerboard = create_vk_image_from_data(pixels.data, VkExtent2D.{ 16, 16 }, .R8G8B8A8_SRGB, .SAMPLED_BIT | .TRANSFER_DST_BIT);
    add_resource(ERROR_TEXTURE_NAME, vk.errorCheckerboard);
}

create_vk_instance :: (appName : string) -> VkResult {
    array_add(*vk.instanceExtensions, VK_KHR_SURFACE_EXTENSION_NAME.data);
    array_add(*vk.instanceExtensions, VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME.data);

    // Make list of extensions to request for each OS we support
    #if OS == .WINDOWS {
	array_add(*vk.instanceExtensions, VK_KHR_WIN32_SURFACE_EXTENSION_NAME.data);
    } else #if OS == .LINUX {
	array_add(*vk.instanceExtensions, VK_KHR_XLIB_SURFACE_EXTENSION_NAME.data);
    } else #if OS == .ANDROID {
	array_add(*vk.instanceExtensions, VK_KHR_ANDROID_SURFACE_EXTENSION_NAME.data);
    }

    // Get supported extensions
    extCount : u32;
    vkEnumerateInstanceExtensionProperties(null, *extCount, null);
    supportedExtensions := NewArray(extCount, VkExtensionProperties);
    defer free(supportedExtensions.data);
    vkEnumerateInstanceExtensionProperties(null, *extCount, supportedExtensions.data);

    // Setup Application and Creation Info
    appInfo : VkApplicationInfo;
    appInfo.pApplicationName = to_c_string(appName);
    appInfo.pEngineName = "Loam";
    appInfo.apiVersion = VK_API_VERSION_1_3;

    createInfo : VkInstanceCreateInfo;
    createInfo.pApplicationInfo = *appInfo;
    
    #if IS_DEV {
	for supportedExtensions {
	    ext := from_array_cstr(it.extensionName);
	    if ext == VK_EXT_DEBUG_UTILS_EXTENSION_NAME {
		array_add(*vk.instanceExtensions, VK_EXT_DEBUG_UTILS_EXTENSION_NAME.data);
		break;
	    }
	}

	debugUtilsCreateInfo : VkDebugUtilsMessengerCreateInfoEXT;
	debugUtilsCreateInfo.messageSeverity = .WARNING_BIT_EXT | .ERROR_BIT_EXT;
	debugUtilsCreateInfo.messageType = .GENERAL_BIT_EXT | .VALIDATION_BIT_EXT;
	debugUtilsCreateInfo.pfnUserCallback = vk_debug_callback;
	
	debugUtilsCreateInfo.pNext = createInfo.pNext;
	createInfo.pNext = *debugUtilsCreateInfo;
    }

    if vk.instanceExtensions.count {
	createInfo.enabledExtensionCount = cast(u32) vk.instanceExtensions.count;
	createInfo.ppEnabledExtensionNames = vk.instanceExtensions.data;
    }

    layerCount : u32;
    vkEnumerateInstanceLayerProperties(*layerCount, null);
    if layerCount == 0 then log_vk(.ERROR, "No Supported Layers found");
    supportedLayers := NewArray(layerCount, VkLayerProperties);
    defer free(supportedLayers.data);
    vkEnumerateInstanceLayerProperties(*layerCount, supportedLayers.data);
    
    #if IS_DEV {
	validationLayerName := "VK_LAYER_KHRONOS_validation";
	for supportedLayers {
    	    layer := from_array_cstr(it.layerName);
	    if compare(layer, validationLayerName) == 0 {
		createInfo.enabledLayerCount = 1;
		createInfo.ppEnabledLayerNames = *validationLayerName.data;
		break;
	    }
	}

	if createInfo.enabledLayerCount == 0 then log_vk(.WARN, "Failed to find validation layer.");
    }

    result := vkCreateInstance(*createInfo, null, *vk.instance);
    
    free(appInfo.pApplicationName);
    
    return result;
}

create_vk_surface :: (window : Window_Type) -> VkResult {
    #if OS == .WINDOWS {
	surfaceCreateInfo := VkWin32SurfaceCreateInfoKHR.{ hinstance = Windows.GetModuleHandleW(null), hwnd = window };
	return vkCreateWin32SurfaceKHR(vk.instance, *surfaceCreateInfo, null, *vk.surface);
    } else #if OS == .LINUX {
	surfaceCreateInfo := VkXlibSurfaceCreateInfoKHR.{ display = X11.x_global_display, window = window};
	return vkCreateXlibSurfaceKHR(vk.instance, *surfaceCreateInfo, null, *vk.surface);
    } else #if OS == .ANDROID {
	surfaceCreateInfo := VkAndroidSurfaceCreateInfoKHR.{ window = window };
	return vkCreateAndroidSurfaceKHR(vk.instance, *surfaceCreateInfo, null, *vk.surface);
    }
    
    return .ERROR_INITIALIZATION_FAILED;
}

get_vk_physical_device :: () -> VkResult {
    array_add(*vk.deviceExtensions, VK_KHR_SWAPCHAIN_EXTENSION_NAME.data);

    vk.reqFeatures_1_0.shaderInt64 = 1;
    vk.reqFeatures_1_0.samplerAnisotropy = 1;
    vk.reqFeatures_1_2.bufferDeviceAddress = 1;
    vk.reqFeatures_1_2.descriptorIndexing = 1;
    vk.reqFeatures_1_2.descriptorBindingPartiallyBound = 1;
    vk.reqFeatures_1_2.descriptorBindingSampledImageUpdateAfterBind = 1;
    vk.reqFeatures_1_2.descriptorBindingVariableDescriptorCount = 1;
    //vk.reqFeatures_1_2.shaderSampledImageArrayNonUniformIndexing = 1;
    vk.reqFeatures_1_2.runtimeDescriptorArray = 1;
    vk.reqFeatures_1_3.dynamicRendering = 1;
    vk.reqFeatures_1_3.synchronization2 = 1;
    
    gpuCount : u32;
    vkEnumeratePhysicalDevices(vk.instance, *gpuCount, null);
    if gpuCount == 0 then return .ERROR_DEVICE_LOST;
    availableDevices := NewArray(gpuCount, VkPhysicalDevice);
    defer free(availableDevices.data);
    check_vk(vkEnumeratePhysicalDevices(vk.instance, *gpuCount, availableDevices.data), "Failed to enumerate physical devices.");

    vk.physicalDevice = find_best_gpu_for_conditions(availableDevices);
    if !vk.physicalDevice {
	log_vk(.FATAL, "Failed to find a valid GPU.");
    }
    
    deviceProperties : VkPhysicalDeviceProperties;
    vkGetPhysicalDeviceProperties(vk.physicalDevice, *deviceProperties);

    log_vk(.SUCCESS, tprint("GPU Selected: %", cast(string) deviceProperties.deviceName));
    
    return .SUCCESS;
}

create_vk_device :: () -> VkResult {
    queueCreateInfos : [..] VkDeviceQueueCreateInfo;
    
    graphicsCreateInfo := queue_create_info(vk.queueFamilyIndices.graphics);
    vk.queueCountsPerFamily.graphics = graphicsCreateInfo.queueCount;
    array_add(*queueCreateInfos, graphicsCreateInfo);
    
    if vk.queueFamilyIndices.compute != vk.queueFamilyIndices.graphics {
	computeCreateInfo := queue_create_info(vk.queueFamilyIndices.compute);
	vk.queueCountsPerFamily.compute = computeCreateInfo.queueCount;
	array_add(*queueCreateInfos, computeCreateInfo);
    }

    if vk.enableVkVideo {
	if vk.queueFamilyIndices.videoDecode != vk.queueFamilyIndices.graphics &&
	   vk.queueFamilyIndices.videoDecode != vk.queueFamilyIndices.compute {
	    videoCreateInfo := queue_create_info(vk.queueFamilyIndices.videoDecode);
	    vk.queueCountsPerFamily.videoDecode = videoCreateInfo.queueCount;
	    array_add(*queueCreateInfos, videoCreateInfo);
	}
    }
    
    deviceCreateInfo := VkDeviceCreateInfo.{};
    deviceCreateInfo.queueCreateInfoCount = cast(u32) queueCreateInfos.count;
    deviceCreateInfo.pQueueCreateInfos = queueCreateInfos.data;

    // NOTE: We've already checked these features and extensions are available when creating the physical device
    featureChain := chain_physical_device_features(*vk.reqFeatures_1_1, *vk.reqFeatures_1_2, *vk.reqFeatures_1_3);
    featureChain.features = vk.reqFeatures_1_0;
    deviceCreateInfo.pNext = *featureChain;
    
    deviceCreateInfo.enabledExtensionCount = cast(u32) vk.deviceExtensions.count;
    deviceCreateInfo.ppEnabledExtensionNames = vk.deviceExtensions.data;

    result := vkCreateDevice(vk.physicalDevice, *deviceCreateInfo, null, *vk.device);

    array_reset(*queueCreateInfos);
    
    return result;
}

create_vk_swapchain :: () -> VkResult {
    oldSwapchain := vk.swapchain;

    surfaceCaps : VkSurfaceCapabilitiesKHR;
    check_vk(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(vk.physicalDevice, vk.surface, *surfaceCaps), "Failed to get surface capabilities");

    // Set swapchain extent
    vk.swapchainExtent = surfaceCaps.currentExtent;
    if vk.swapchainExtent.width == U32_MAX || vk.swapchainExtent.height == U32_MAX {
	vk.swapchainExtent.width  = cast(u32) clamp(loam.windowWidth, surfaceCaps.minImageExtent.width, surfaceCaps.maxImageExtent.width);
	vk.swapchainExtent.height = cast(u32) clamp(loam.windowHeight, surfaceCaps.minImageExtent.height, surfaceCaps.maxImageExtent.height);
    }

    loam.sceneCamera.dimensions = .{ cast(float) vk.swapchainExtent.width, cast(float) vk.swapchainExtent.height };
    loam.uiCamera.dimensions = .{ cast(float) vk.swapchainExtent.width, cast(float) vk.swapchainExtent.height };

    // Get best present mode for our purposes
    presentModeCount : u32;
    check_vk(vkGetPhysicalDeviceSurfacePresentModesKHR(vk.physicalDevice, vk.surface, *presentModeCount, null), "Failed to get valid present modes for the current surface from the physical device");
    if presentModeCount == 0 {
	log_vk(.FATAL, "No present modes found for surface, this goes against the Vulkan spec as not even FIFO was found.");
	return .ERROR_SURFACE_LOST_KHR;
    }
    presentModes := NewArray(presentModeCount, VkPresentModeKHR);
    defer free(presentModes.data);
    check_vk(vkGetPhysicalDeviceSurfacePresentModesKHR(vk.physicalDevice, vk.surface, *presentModeCount, presentModes.data), "Failed to get valid present modes for the current surface from the physical device");

    selectedPresentMode := VkPresentModeKHR.FIFO_KHR;

    // TODO: Get this from a setting struct of some kind, we should probably also force vsync on android (I don't think there's any reason not to)
    if vk.vsync {
	for presentModes {
	    if it == .MAILBOX_KHR {
		selectedPresentMode = it;
		break;
	    }
	}
    } else {
	for presentModes {
	    if it == .IMMEDIATE_KHR {
		selectedPresentMode = it;
		break;
	    }
	}
    }

    // Get Image count
    swapchainImageCount := surfaceCaps.minImageCount + 1;
    if surfaceCaps.maxImageCount > 0 && swapchainImageCount > surfaceCaps.maxImageCount {
	swapchainImageCount := surfaceCaps.maxImageCount;
    }

    // Get the basic transform for the surface if it exists
    preTransform := surfaceCaps.currentTransform;
    if surfaceCaps.supportedTransforms & .IDENTITY_BIT_KHR then preTransform = .IDENTITY_BIT_KHR;

    // Get the best alpha composition for the window (because not all devices support Alpha Opaque
    windowCompositeAlpha := VkCompositeAlphaFlagBitsKHR.OPAQUE_BIT_KHR;
    compositeAlphaFlags := VkCompositeAlphaFlagBitsKHR.[ .OPAQUE_BIT_KHR, .PRE_MULTIPLIED_BIT_KHR, .POST_MULTIPLIED_BIT_KHR, .INHERIT_BIT_KHR ];
    for compositeAlphaFlags {
	if surfaceCaps.supportedCompositeAlpha & it {
	    windowCompositeAlpha = it;
	    break;
	}
    }

    // Get colour format and colour space
    formatCount : u32;
    check_vk(vkGetPhysicalDeviceSurfaceFormatsKHR(vk.physicalDevice, vk.surface, *formatCount, null), "Failed to get supported surface formats");
    if formatCount == 0 {
	log_vk(.FATAL, "No formats found for surface.");
	return .ERROR_SURFACE_LOST_KHR;
    }
    surfaceFormats := NewArray(formatCount, VkSurfaceFormatKHR);
    defer free(surfaceFormats.data);
    check_vk(vkGetPhysicalDeviceSurfaceFormatsKHR(vk.physicalDevice, vk.surface, *formatCount, surfaceFormats.data), "Failed to get supported surface formats");

    selectedFormat := surfaceFormats[0];
    preferredFormats := VkFormat.[ .R8G8B8A8_SRGB, .B8G8R8A8_SRGB ];
    for supportedFormat : surfaceFormats {
	for preferredFormats {
	    if supportedFormat.format == it && supportedFormat.colorSpace == .COLOR_SPACE_SRGB_NONLINEAR_KHR {
		selectedFormat = supportedFormat;
		break supportedFormat;
	    }
	}
    }

    colourFormat := selectedFormat.format;
    colourSpace := selectedFormat.colorSpace;
    
    // Get supported usage flags we want
    // TODO: Do we want to error if we don't at least get the dest bit?
    usageFlags := VkImageUsageFlags.COLOR_ATTACHMENT_BIT;
    if surfaceCaps.supportedUsageFlags & .TRANSFER_SRC_BIT then usageFlags |= .TRANSFER_SRC_BIT;
    if surfaceCaps.supportedUsageFlags & .TRANSFER_DST_BIT then usageFlags |= .TRANSFER_DST_BIT;
    
    createInfo := VkSwapchainCreateInfoKHR.{ .SWAPCHAIN_CREATE_INFO_KHR, null, 0,
	vk.surface, swapchainImageCount, colourFormat, colourSpace, .{ vk.swapchainExtent.width, vk.swapchainExtent.height }, 1, usageFlags, .EXCLUSIVE,
	0, null, preTransform, windowCompositeAlpha, selectedPresentMode, VK_TRUE, oldSwapchain };
    check_vk(vkCreateSwapchainKHR(vk.device, *createInfo, null, *vk.swapchain), "Failed to create swapchain");

    vk.swapchainFormat = colourFormat;

    log_vk(.INFO, "Created Swapchain");
    log_vk(.INFO, tprint("Swapchain Extent: %", vk.swapchainExtent));
    log_vk(.INFO, tprint("Swapchain Present Mode: %", selectedPresentMode));
    log_vk(.INFO, tprint("Swapchain Image Count: %", swapchainImageCount));
    log_vk(.INFO, tprint("Swapchain Transform: %", preTransform));
    log_vk(.INFO, tprint("Swapchain Composite Alpha: %", windowCompositeAlpha));
    log_vk(.INFO, tprint("Swapchain Colour Format: %", colourFormat));
    log_vk(.INFO, tprint("Swapchain Colour Space: %", colourSpace));
    log_vk(.INFO, tprint("Swapchain Usage Flags: %", usageFlags));

    // Clear out the old swapchain
    // NOTE: We don't need to destroy the images because they're owned by the swapchain itself
    if oldSwapchain {
	for * vk.swapchainImageViews {
	    vkDestroyImageView(vk.device, it.*, null);
	}
	vkDestroySwapchainKHR(vk.device, oldSwapchain, null);

	destroy_vk_image(vk.drawImage);
    }

    imageCount : u32;
    check_vk(vkGetSwapchainImagesKHR(vk.device, vk.swapchain, *imageCount, null), "Failed to get images from swapchain");
    array_resize(*vk.swapchainImages, imageCount);
    check_vk(vkGetSwapchainImagesKHR(vk.device, vk.swapchain, *imageCount, vk.swapchainImages.data), "Failed to get images from swapchain");

    array_resize(*vk.swapchainImageViews, imageCount);
    for 0 .. imageCount-1 {
	imgViewCreateInfo : VkImageViewCreateInfo;
	imgViewCreateInfo.image = vk.swapchainImages[it];
	imgViewCreateInfo.viewType = ._2D;
	imgViewCreateInfo.format = colourFormat;
	imgViewCreateInfo.components = .{ .R, .G, .B, .A };
	imgViewCreateInfo.subresourceRange = .{ .COLOR_BIT, 0, 1, 0, 1 };
	check_vk(vkCreateImageView(vk.device, *imgViewCreateInfo, null, *vk.swapchainImageViews[it]), tprint("Failed to create image view for swapchain image: %", it));
    }

    // Make Draw Image
    // TODO: Make Depth Image
    vk.drawImage = create_vk_image(vk.swapchainExtent, .R16G16B16A16_SFLOAT, .TRANSFER_DST_BIT | .TRANSFER_SRC_BIT | .STORAGE_BIT | .COLOR_ATTACHMENT_BIT, 0);
    
    return .SUCCESS;
}

#load "bindless_descriptors.jai";
//#load "descriptors.jai";
#load "mesh.jai";
#load "pipelines.jai";
#load "render.jai";
#load "render_commands.jai";
#load "shaders.jai";
#load "update_commands.jai";
#load "util.jai";
