/*
Project: Loam
File: vk/util.jai
Author: Brock Salmon
Created: 27APR2025
*/

FENCE_WAIT_TIME :: #run seconds_to_nanoseconds(1);

resize_swapchain :: () {
    vkDeviceWaitIdle(vk.device);
    check_vk(create_vk_swapchain(), "Failed to recreate swapchain when resizing window");
    vk.resizeRequested = false;
}

find_best_gpu_for_conditions :: (availableDevices : [] VkPhysicalDevice) -> VkPhysicalDevice {
    bestGPU : VkPhysicalDevice = null;

    // Filter out invalid physical devices
    validGPUs : [..] VkPhysicalDevice;
    for device : availableDevices {
	deviceProperties : VkPhysicalDeviceProperties;
	vkGetPhysicalDeviceProperties(device, *deviceProperties);
	
	// Check Vulkan 1.3 is supported
	// NOTE: WSL2 doesn't recognise Vulkan 1.3 and the dozen driver will only report 1.2 even if 1.3 is actually supported, so we skip this check for linux.
	if OS != .LINUX && deviceProperties.apiVersion < VK_API_VERSION_1_3 {
	    log_vk(.INFO, tprint("Physical Device: % is not valid due to not meeting the minimum API version, version was: %.%.%", to_string(deviceProperties.deviceName.data),
				 VK_VERSION_MAJOR(deviceProperties.apiVersion), VK_VERSION_MINOR(deviceProperties.apiVersion), VK_VERSION_PATCH(deviceProperties.apiVersion)));
	    continue;
	}

	// Check queue families have the queues we need available
	queueFamilyCount : u32;
	vkGetPhysicalDeviceQueueFamilyProperties(device, *queueFamilyCount, null);
	queueFamilies, queueArrayData := NewArray(queueFamilyCount, VkQueueFamilyProperties);
	defer free(queueArrayData);
	vkGetPhysicalDeviceQueueFamilyProperties(device, *queueFamilyCount, queueFamilies.data);

	usedIndices : [..] u32;
	if !get_queue_family_index(.GRAPHICS_BIT, queueFamilies, *usedIndices, deviceProperties) {
	    array_reset(*usedIndices);
	    continue;
	}
	if !get_queue_family_index(.COMPUTE_BIT, queueFamilies, *usedIndices, deviceProperties) {
	    array_reset(*usedIndices);
	    continue;
	}
	
	array_reset(*usedIndices);
	
	// Check features are available
	// TODO: We probably need a way to establish if a feature is really needed or not.
	features_1_1     : VkPhysicalDeviceVulkan11Features;
	features_1_2     : VkPhysicalDeviceVulkan12Features;
	features_1_3     : VkPhysicalDeviceVulkan13Features;
	features_Robust  : VkPhysicalDeviceRobustness2FeaturesEXT;
	featureChain := chain_physical_device_features(*features_1_1, *features_1_2, *features_1_3, *features_Robust);
	vkGetPhysicalDeviceFeatures2(device, *featureChain);
	features_1_0 := featureChain.features;

	typeInfos := Type_Info_Struct.[ type_info(VkPhysicalDeviceFeatures), type_info(VkPhysicalDeviceVulkan11Features),
					type_info(VkPhysicalDeviceVulkan12Features), type_info(VkPhysicalDeviceVulkan13Features),
				        type_info(VkPhysicalDeviceRobustness2FeaturesEXT)];

	allFeaturesSupported := true;
	for info : typeInfos {
	    infoIndex := it_index;
	    for member : info.members {
		if member.name == "sType" || member.name == "pNext" then continue;

		offset := member.offset_in_bytes;
		get_member_at_offset :: (features : *void) -> VkBool32 #expand {
		    return (cast(*VkBool32) (cast(*u8) features + `offset)).*;
		}

		requested : VkBool32;
		supported : VkBool32;

		if infoIndex == {
		    case 0; {
			requested = get_member_at_offset(*vk.reqFeatures_1_0);
			supported = get_member_at_offset(*features_1_0);
		    }
		    case 1; {
			requested = get_member_at_offset(*vk.reqFeatures_1_1);
			supported = get_member_at_offset(*features_1_1);
		    }
		    case 2; {
			requested = get_member_at_offset(*vk.reqFeatures_1_2);
			supported = get_member_at_offset(*features_1_2);
		    }
		    case 3; {
			requested = get_member_at_offset(*vk.reqFeatures_1_3);
			supported = get_member_at_offset(*features_1_3);
		    }
		    case 4; {
			requested = get_member_at_offset(*vk.reqFeatures_Robust);
			supported = get_member_at_offset(*features_Robust);
		    }
		    case; assert(false, "Invalid feature struct type info index");
		}

		if requested && !supported {
		    allFeaturesSupported = false;
		    break info;
		}
	    }
	}

	if !allFeaturesSupported {
	    log_vk(.INFO, tprint("Physical Device: % is not valid due to not supporting all requested features", to_string(deviceProperties.deviceName.data)));
	    continue;
	}

	// Check if extensions are available
	extCount : u32;
	vkEnumerateDeviceExtensionProperties(device, null, *extCount, null);
	extensions, extArrayData := NewArray(extCount, VkExtensionProperties);
	defer free(extArrayData);
	vkEnumerateDeviceExtensionProperties(device, null, *extCount, extensions.data);

	allExtensionsSupported := true;
	for vk.deviceExtensions {
	    requested := to_string(it);
	    
	    foundExt := false;
	    for extensions {
		ext := cast(string) it.extensionName;
		ext.count = find_index_from_left(ext, "\0");
		if requested == ext {
		    foundExt = true;
		    break;
		}
	    }
	    
	    if !foundExt {
		allExtensionsSupported = false;
		break;
	    }
	}

	if !allExtensionsSupported {
	    log_vk(.INFO, tprint("Physical Device: % is not valid due to not supporting all requested extensions", to_string(deviceProperties.deviceName.data)));
	    continue;
	}

	array_add(*validGPUs, device);
    }

    // Select a GPU out of the best available options, prefer discrete
    bestScore := 0;
    for validGPUs {
	score := 0;

	// Find what we determine to be the best performing GPU
	properties : VkPhysicalDeviceProperties;
	vkGetPhysicalDeviceProperties(it, *properties);

	memoryKB := properties.limits.maxMemoryAllocationCount * size_of(VkDeviceSize) / 1024;
	print("Memory (KB): %\n\n", memoryKB);
	score += memoryKB;
	
	if score > bestScore {
	    bestScore = score;
	    bestGPU = it;
	}
    }

    array_reset(*validGPUs);

    if bestGPU {
	deviceProperties : VkPhysicalDeviceProperties;
	vkGetPhysicalDeviceProperties(bestGPU, *deviceProperties);
	
	queueFamilyCount : u32;
	vkGetPhysicalDeviceQueueFamilyProperties(bestGPU, *queueFamilyCount, null);
	queueFamilies, queueArrayData := NewArray(queueFamilyCount, VkQueueFamilyProperties);
	defer free(queueArrayData);
	vkGetPhysicalDeviceQueueFamilyProperties(bestGPU, *queueFamilyCount, queueFamilies.data);

	// NOTE: We know these all already exist how we want them from the filter stage, so ignore the found result
	usedIndices : [..] u32;
	_, vk.queueFamilyIndices.graphics    = get_queue_family_index(.GRAPHICS_BIT, queueFamilies, *usedIndices, deviceProperties);
	_, vk.queueFamilyIndices.compute     = get_queue_family_index(.COMPUTE_BIT, queueFamilies, *usedIndices, deviceProperties);
	vk.enableVkVideo, vk.queueFamilyIndices.videoDecode = get_queue_family_index(.VIDEO_DECODE_BIT_KHR, queueFamilies, *usedIndices, deviceProperties);
	array_reset(*usedIndices);
    }
    
    return bestGPU;
}

select_texture_format :: () {
    #if OS == .ANDROID {
	acceptableFormats := VkFormat.[
		.ASTC_4x4_SRGB_BLOCK, // Android
		.ETC2_R8G8B8A8_SRGB_BLOCK, // Android
	];
    } else {
	acceptableFormats := VkFormat.[
		.BC7_SRGB_BLOCK, // PC
		.BC3_SRGB_BLOCK, // PC
	];
    }

    for acceptableFormats {
	formatProperties : VkFormatProperties;
	vkGetPhysicalDeviceFormatProperties(vk.physicalDevice, it, *formatProperties);

	supportsTransfer := formatProperties.optimalTilingFeatures & VkFormatFeatureFlags.TRANSFER_DST_BIT  != 0;
	supportsSampled  := formatProperties.optimalTilingFeatures & VkFormatFeatureFlags.SAMPLED_IMAGE_BIT != 0;

	if supportsTransfer && supportsSampled {
	    vk.textureFormat = it;
	    return;
	}
    }
}

get_dedicated_queue_family_index :: (flag : VkQueueFlags, queueFamilies : [] VkQueueFamilyProperties, usedIndices : *[..] u32) -> bool, u32 {
    bestIndex := U32_MAX;
    
    for queueFamilies {
	index := cast(u32) it_index;
	if (flag & it.queueFlags) == flag {
	    bestIndex = index;
	    if !is_in_array(index, usedIndices.*) {
		array_add(usedIndices, index);
		return true, index;
	    }
	}
    }
    
    if bestIndex == U32_MAX {
	return false, 0;
    } else {
	return true, bestIndex;
    }
}

get_any_queue_family_index :: (flag : VkQueueFlags, queueFamilies : [] VkQueueFamilyProperties) -> bool, u32 {
    for queueFamilies {
	if (flag & it.queueFlags) == flag {
	    return true, cast(u32) it_index;
	}
    }

    return false, 0;
}

get_queue_family_index :: (flag : VkQueueFlags, queueFamilies : [] VkQueueFamilyProperties, usedIndices : *[..] u32, deviceProps : VkPhysicalDeviceProperties) -> bool, u32 {
    found, index := get_dedicated_queue_family_index(flag, queueFamilies, usedIndices);
    if !found {
	log_vk(.INFO, tprint("Failed to find a dedicated Queue Family Index for flags: % on %, finding any available index with flag", flag, to_string(deviceProps.deviceName.data)));
	found, index = get_any_queue_family_index(flag, queueFamilies);
	if !found {
	    log_vk(.INFO, tprint("Failed to find any Queue Family Index for flags: % on %", flag, to_string(deviceProps.deviceName.data)));
	}
    }

    return found, index;
}

chain_physical_device_features :: (_1_1 : *VkPhysicalDeviceVulkan11Features, _1_2 : *VkPhysicalDeviceVulkan12Features, _1_3 : *VkPhysicalDeviceVulkan13Features, robustness : *VkPhysicalDeviceRobustness2FeaturesEXT) -> VkPhysicalDeviceFeatures2 {
    featureChain : VkPhysicalDeviceFeatures2;
    featureChain.pNext = _1_1;
    _1_1.pNext = _1_2;
    _1_2.pNext = _1_3;
    _1_3.pNext = robustness;

    return featureChain;
}

queue_create_info :: (familyIndex : u32) -> VkDeviceQueueCreateInfo {
    queueFamilyCount : u32;
    vkGetPhysicalDeviceQueueFamilyProperties(vk.physicalDevice, *queueFamilyCount, null);
    queueFamilies := NewArray(queueFamilyCount, VkQueueFamilyProperties,, temp);
    vkGetPhysicalDeviceQueueFamilyProperties(vk.physicalDevice, *queueFamilyCount, queueFamilies.data);

    queueCount := queueFamilies[familyIndex].queueCount;
    priorities := NewArray(queueCount, float32,, temp);
    for * priorities {
	it.* = 1; // Set priority of all queues to 1
    }
    
    queueInfo := VkDeviceQueueCreateInfo.{};
    queueInfo.queueFamilyIndex = familyIndex;
    queueInfo.queueCount = queueCount;
    queueInfo.pQueuePriorities = priorities.data;

    return queueInfo;
}

// Returns the lowest available queue count out of the active queue families
// TODO: When we start using the compute (and video on PC) queues, we probably need to restructure the threading system to have a system per queue family
get_lowest_queue_count :: () -> u32 {
    #if OS == .WINDOWS {
	queueCount := min(vk.queueCountsPerFamily.graphics, vk.queueCountsPerFamily.compute);
    } else {
	queueCount := vk.queueCountsPerFamily.graphics;
    }
    
    //if vk.enableVkVideo then queueCount = min(queueCount, vk.queueCountsPerFamily.videoDecode);
    // TODO: Video queue if it has issues with multithreading later. removed as most video queue families seem to only have 1 queue
    
    return queueCount;
}

create_vk_image :: (extent : VkExtent2D, format : VkFormat, usage : VkImageUsageFlags, fenceIndex : s64, mipmapped := false) -> *AllocatedImageInfo {
    createInfo := VkImageCreateInfo.{ .IMAGE_CREATE_INFO, null, 0, ._2D, format, .{ extent.width, extent.height, 1 }, 1, 1, ._1_BIT, .OPTIMAL, usage, .EXCLUSIVE, 0, null, .UNDEFINED };
    if mipmapped then createInfo.mipLevels = cast(u32) floor(log2(cast(float) max(extent.width, extent.height))) + 1;
    allocationCreateInfo := VmaAllocationCreateInfo.{ usage = .AUTO, flags = .DEDICATED_MEMORY_BIT };

    image := New(AllocatedImageInfo);
    check_vk(vmaCreateImage(vk.allocator, *createInfo, *allocationCreateInfo, *image.image, *image.allocation, null), "Failed to create Image");
    
    image.extent = extent;
    image.format = format;
    
    aspectMask : VkImageAspectFlags = ifx format == .D32_SFLOAT then .DEPTH_BIT else .COLOR_BIT;
    viewCreateInfo := VkImageViewCreateInfo.{ .IMAGE_VIEW_CREATE_INFO, null, 0, image.image, ._2D, format, .{}, make_image_subresource_range(aspectMask, 1, 1) };
    check_vk(vkCreateImageView(vk.device, *viewCreateInfo, null, *image.view), "Failed to create Image View");
    
    return image;
}

DataCopyData :: struct {
    buffer : *AllocatedBufferInfo;
    image : *AllocatedImageInfo;
    extent : VkExtent2D;
}

create_vk_image_from_data :: (data : *void, extent : VkExtent2D, format : VkFormat, usage : VkImageUsageFlags, bytesPerPixel : u64 = 4, mipmapped := false) -> *AllocatedImageInfo {
    dataSize := extent.width * extent.height * bytesPerPixel;
    uploadBuffer := create_vk_buffer(dataSize, .TRANSFER_SRC_BIT);
    memcpy(uploadBuffer.allocationInfo.pMappedData, data, cast(s64) dataSize);
    
    image := create_vk_image(extent, format, usage, 0, mipmapped);
    
    imm_copy_into_image :: (cmdBuffer : VkCommandBuffer, data : *void) {
	copyData := cast(*DataCopyData) data;

	transition_image(cmdBuffer, copyData.image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL);
	copyRegion := VkBufferImageCopy.{ 0, 0, 0, VkImageSubresourceLayers.{ .COLOR_BIT, 0, 0, 1 }, .{}, .{ copyData.extent.width, copyData.extent.height, 1 } };
	vkCmdCopyBufferToImage(cmdBuffer, copyData.buffer.buffer, copyData.image.image, .TRANSFER_DST_OPTIMAL, 1, *copyRegion);
	transition_image(cmdBuffer, copyData.image.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL);
    }
    
    imageCopyData := New(DataCopyData);
    imageCopyData.* = .{ uploadBuffer, image, extent };
    
    buffersToCleanup := pack_buffers_for_cleanup(uploadBuffer);
    add_update_command_work(imm_copy_into_image, imageCopyData, buffersToCleanup);
    
    return image;
}

KTXCopyData :: struct {
    buffer : *AllocatedBufferInfo;
    image : AllocatedImageInfo;
    ktx : *ktxTexture2;
}

create_vk_image_from_ktx :: (ktx : *ktxTexture2) -> *AllocatedImageInfo {
    createInfo := VkImageCreateInfo.{ .IMAGE_CREATE_INFO, null, 0, ._2D,
				      cast(VkFormat) ktx.vkFormat, .{ ktx.baseWidth, ktx.baseHeight, 1 }, ktx.numLevels, ktx.numLayers * ktx.numFaces, ._1_BIT,
				      .OPTIMAL, .SAMPLED_BIT | .TRANSFER_DST_BIT, .EXCLUSIVE, 0, null, .UNDEFINED };
    allocationCreateInfo := VmaAllocationCreateInfo.{ usage = .GPU_ONLY, requiredFlags = .DEVICE_LOCAL_BIT };

    image := New(AllocatedImageInfo);
    check_vk(vmaCreateImage(vk.allocator, *createInfo, *allocationCreateInfo, *image.image, *image.allocation, null), "Failed to create Image");
    
    image.extent = .{ ktx.baseWidth, ktx.baseHeight };
    image.format = cast(VkFormat) ktx.vkFormat;
    
    aspectMask := VkImageAspectFlags.COLOR_BIT;
    viewCreateInfo := VkImageViewCreateInfo.{ .IMAGE_VIEW_CREATE_INFO, null, 0, image.image, ._2D, cast(VkFormat) ktx.vkFormat, .{}, make_image_subresource_range(aspectMask, 1, 1) };
    check_vk(vkCreateImageView(vk.device, *viewCreateInfo, null, *image.view), "Failed to create Image View");

    dataSize := ktxTexture_GetDataSize(ktx);
    uploadBuffer := create_vk_buffer(dataSize, .TRANSFER_SRC_BIT);
    memcpy(uploadBuffer.allocationInfo.pMappedData, ktx.pData, cast(s64) dataSize);
    
    imm_copy_into_image :: (cmdBuffer : VkCommandBuffer, data : *void) {
	copyData := cast(*KTXCopyData) data;

	transition_image(cmdBuffer, copyData.image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL);

	for level : 0 .. copyData.ktx.numLevels-1 {
	    for layer : 0 .. (copyData.ktx.numLayers * copyData.ktx.numFaces)-1 {
		offset, imageSize : u64;
		ktxTexture_GetImageOffset(copyData.ktx, level, layer / copyData.ktx.numFaces, layer % copyData.ktx.numFaces, *offset);
		imageSize = ktxTexture_GetImageSize(copyData.ktx, level);

		copyRegion := VkBufferImageCopy.{ offset, 0, 0, VkImageSubresourceLayers.{ .COLOR_BIT, level, layer, 1 }, .{},
						  .{ cast(u32) max(1, copyData.ktx.baseWidth >> level), cast(u32) max(1, copyData.ktx.baseHeight >> level), 1 } };

		vkCmdCopyBufferToImage(cmdBuffer, copyData.buffer.buffer, copyData.image.image, .TRANSFER_DST_OPTIMAL, 1, *copyRegion);
	    }
	}
	
	transition_image(cmdBuffer, copyData.image.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL);
    }
    
    imageCopyData := New(KTXCopyData);
    imageCopyData.* = .{ uploadBuffer, image, ktx };
    
    buffersToCleanup := pack_buffers_for_cleanup(uploadBuffer);
    add_update_command_work(imm_copy_into_image, imageCopyData, buffersToCleanup);
    
    return image;
}

destroy_vk_image :: (image : *AllocatedImageInfo) {
    for vk.frames {
	check_vk(vkWaitForFences(vk.device, 1, *it.renderFence, VK_TRUE, FENCE_WAIT_TIME), tprint("Failed to wait for fence for Frame %", it_index));
    }
    vkDestroyImageView(vk.device, image.view, null);
    vmaDestroyImage(vk.allocator, image.image, image.allocation);
    free(image);
}

cleanup_single_frame_images :: () {
    for * vk.imagesToDestroyAtFrameReset {
	destroy_vk_image(it.*);
	it = null;
    }

    array_reset(*vk.imagesToDestroyAtFrameReset);
}

create_vk_buffer :: (size : u64, usage : VkBufferUsageFlags) -> *AllocatedBufferInfo {
    createInfo := VkBufferCreateInfo.{ size = size, usage = usage };
    allocationCreateInfo := VmaAllocationCreateInfo.{ flags = .MAPPED_BIT | .HOST_ACCESS_SEQUENTIAL_WRITE_BIT, usage = .AUTO };

    buffer := New(AllocatedBufferInfo);
    check_vk(vmaCreateBuffer(vk.allocator, *createInfo, *allocationCreateInfo, *buffer.buffer, *buffer.allocation, *buffer.allocationInfo), "Failed to create Buffer");
    
    return buffer;
}

destroy_vk_buffer :: (buffer : *AllocatedBufferInfo) {
    vmaDestroyBuffer(vk.allocator, buffer.buffer, buffer.allocation);
    free(buffer);
}

cleanup_single_frame_buffers :: () {
    for * vk.buffersToDestroyAtFrameReset {
	destroy_vk_buffer(it.*);
	it = null;
    }

    array_reset(*vk.buffersToDestroyAtFrameReset);
}

make_image_subresource_range :: (aspectMask : VkImageAspectFlags, levelCount : u32 = 0xffffffff, layerCount : u32 = 0xffffffff) -> VkImageSubresourceRange {
    return VkImageSubresourceRange.{ aspectMask, 0, levelCount, 0, layerCount };
}

make_semaphore_submit_info :: (semaphore : VkSemaphore, stageMask : VkPipelineStageFlags2) -> VkSemaphoreSubmitInfo {
    return VkSemaphoreSubmitInfo.{ .SEMAPHORE_SUBMIT_INFO, null, semaphore, 1, stageMask, 0 };
}

make_shader_stage_info :: (shaderStageFlags : VkShaderStageFlags, shader : VkShaderModule) -> VkPipelineShaderStageCreateInfo {
    return VkPipelineShaderStageCreateInfo.{ .PIPELINE_SHADER_STAGE_CREATE_INFO, null, 0, shaderStageFlags, shader, "main\0".data, null };
}

make_rendering_attachment_info :: (view : VkImageView, clear : *VkClearValue = null, layout : VkImageLayout = .COLOR_ATTACHMENT_OPTIMAL) -> VkRenderingAttachmentInfo {
    return VkRenderingAttachmentInfo.{
        imageView = view,
        imageLayout = layout,
        loadOp = ifx clear then .CLEAR else .LOAD,
        storeOp = .STORE,
        clearValue = ifx clear then clear.* else .{},
    };
}

make_rendering_info :: (renderExtent : VkExtent2D, colourAttachment : *VkRenderingAttachmentInfo, depthAttachment : *VkRenderingAttachmentInfo) -> VkRenderingInfo {
    return VkRenderingInfo.{
        renderArea = .{ .{}, renderExtent },
        layerCount = 1,
        colorAttachmentCount = 1,
        pColorAttachments = colourAttachment,
        pDepthAttachment = depthAttachment,
    };
}

extent_to_vector :: (extent : VkExtent2D) -> Vector2 {
    return Vector2.{ cast(float) extent.width, cast(float) extent.height };
}

extent_to_vector :: (extent : VkExtent2D, z : float) -> Vector3 {
    return Vector3.{ cast(float) extent.width, cast(float) extent.height, z };
}

extent_to_vector :: (extent : VkExtent3D) -> Vector3 {
    return Vector3.{ cast(float) extent.width, cast(float) extent.height, cast(float) extent.depth };
}

vk_debug_callback :: (messageSeverity : VkDebugUtilsMessageSeverityFlagBitsEXT, messageType : VkDebugUtilsMessageTypeFlagsEXT, pCallbackData : *VkDebugUtilsMessengerCallbackDataEXT, pUserData : *void) -> VkBool32 #c_call {
    logType := Log_Type.DEV;
    if messageSeverity & .WARNING_BIT_EXT then logType = .WARN;
    if messageSeverity & .ERROR_BIT_EXT then logType = .ERROR;

    push_context {
        print("VALIDATION: %\n", to_string(pCallbackData.pMessage));
        log_vk(logType, tprint("VALIDATION: %", to_string(pCallbackData.pMessage)));
    }

    return VK_FALSE;
}

check_vk :: (result : VkResult, errMsg : string, errType := Log_Type.FATAL, callLoc := #caller_location) {
    if result != .SUCCESS {
        log_vk(errType, tprint("%: %", errMsg, enum_value_to_name(result)), callLoc);
    }
}

log_vk :: (type : Log_Type, s : string, callLoc := #caller_location) {
    log(type, tprint("[VULKAN] %", s), callLoc);
}
