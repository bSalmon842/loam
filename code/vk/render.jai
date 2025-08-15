/*
Project: Loam
File: vk/render.jai
Author: Brock Salmon
Created: 17MAY2025
*/

DEFAULT_TEXTURE_TINT :: Vector4.{1,1,1,1};

Renderable :: struct {
    texture : *ImageResource;
    vertices : [] Vertex;
    vertexMemory : *void;
    
    dimensions : Vector3;
    tint : Vector4 = DEFAULT_TEXTURE_TINT;
    
    buffers : *MeshBuffers;
}

get_current_frame :: () -> *FrameCommandInfo {
    return *vk.frames[vk.currentFrameIndex % FRAMES_IN_FLIGHT];
}

draw_frame :: () {
    check_vk(vkWaitForFences(vk.device, 1, *vk.currentFrame.renderFence, VK_TRUE, FENCE_WAIT_TIME), "(draw_frame) vkWaitForFences failed");
    check_vk(vkResetFences(vk.device, 1, *vk.currentFrame.renderFence), "vkResetFences failed");
    
    swapchainImageIndex : u32;
    acquireResult := vkAcquireNextImageKHR(vk.device, vk.swapchain, seconds_to_nanoseconds(1), vk.currentFrame.swapSemaphore, null, *swapchainImageIndex);
    if acquireResult == .ERROR_OUT_OF_DATE_KHR {
	vk.resizeRequested = true;
        log(.INFO, "Vulkan has requested a resize from vkAcquireNextImageKHR");
	return;
    } else {
	check_vk(acquireResult, "Failed to get next image from swapchain");
    }
    currentSwapchainImage := vk.swapchainImages[swapchainImageIndex];

    drawExtent := VkExtent2D.{
	cast(u32) min(vk.swapchainExtent.width, vk.drawImage.extent.width),
	cast(u32) min(vk.swapchainExtent.height, vk.drawImage.extent.height)
    };

    cmdBuffer := vk.currentFrame.cmdBuffer;
    check_vk(vkResetCommandBuffer(cmdBuffer, 0), tprint("Failed to reset Command Buffer for frame %", vk.currentFrame));
    
    cmdBufferBeginInfo := VkCommandBufferBeginInfo.{ .COMMAND_BUFFER_BEGIN_INFO, null, .ONE_TIME_SUBMIT_BIT, null };
    check_vk(vkBeginCommandBuffer(cmdBuffer, *cmdBufferBeginInfo), tprint("Failed to begin Command Buffer for frame %", vk.currentFrame));

    transition_image(cmdBuffer, vk.drawImage.image, .UNDEFINED, .GENERAL);

    render_clear(cmdBuffer, vk.drawImage.image, .{0.1, 0.1, 0.1, 1.0});
    
    transition_image(cmdBuffer, vk.drawImage.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL);
    
    for * vk.pipelines {
	draw_pipeline(cmdBuffer, it, drawExtent);
    }
    
    transition_image(cmdBuffer, vk.drawImage.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL);
    transition_image(cmdBuffer, currentSwapchainImage, .UNDEFINED, .TRANSFER_DST_OPTIMAL);

    copy_image(cmdBuffer, vk.drawImage.image, drawExtent, currentSwapchainImage, vk.swapchainExtent);

    transition_image(cmdBuffer, currentSwapchainImage, .TRANSFER_DST_OPTIMAL, .PRESENT_SRC_KHR);
    
    check_vk(vkEndCommandBuffer(cmdBuffer), tprint("Failed to end Command Buffer for frame %", vk.currentFrame));

    // Submit Command Buffer to Queue
    cmdInfo := VkCommandBufferSubmitInfo.{ commandBuffer=cmdBuffer };
    waitInfo := make_semaphore_submit_info(vk.currentFrame.swapSemaphore, .COLOR_ATTACHMENT_OUTPUT_BIT);
    signalInfo := make_semaphore_submit_info(vk.currentFrame.renderSemaphore, .ALL_GRAPHICS_BIT);
    submitInfo := VkSubmitInfo2.{ .SUBMIT_INFO_2, null, 0, 1, *waitInfo, 1, *cmdInfo, 1, *signalInfo };
    check_vk(vkQueueSubmit2(vk.graphicsQueue, 1, *submitInfo, vk.currentFrame.renderFence), tprint("Failed to submit Queue for frame %", vk.currentFrame));

    // Present Queue
    presentInfo := VkPresentInfoKHR.{ .PRESENT_INFO_KHR, null, 1, *vk.currentFrame.renderSemaphore, 1, *vk.swapchain, *swapchainImageIndex, null };
    presentResult := vkQueuePresentKHR(vk.graphicsQueue, *presentInfo);
    if presentResult == .ERROR_OUT_OF_DATE_KHR {
	vk.resizeRequested = true;
        log(.INFO, "Vulkan has requested a resize from vkQueuePresentKHR");
	return;
    } else if presentResult != .SUBOPTIMAL_KHR {
	check_vk(presentResult, tprint("Failed to present queue for frame %", vk.currentFrame));
    }
    
    vk.currentFrameIndex = (vk.currentFrameIndex + 1) % FRAMES_IN_FLIGHT;
}

transition_image :: (cmdBuffer : VkCommandBuffer, image : VkImage, currentLayout : VkImageLayout, newLayout : VkImageLayout) {
    range := make_image_subresource_range(ifx newLayout == .DEPTH_ATTACHMENT_OPTIMAL then .DEPTH_BIT else .COLOR_BIT);
    imageBarrier := VkImageMemoryBarrier2.{.IMAGE_MEMORY_BARRIER_2, null, .ALL_COMMANDS_BIT, .MEMORY_WRITE_BIT, .ALL_COMMANDS_BIT, .MEMORY_WRITE_BIT | .MEMORY_READ_BIT, currentLayout, newLayout, 0, 0, image, range };
    dependencies := VkDependencyInfo.{ imageMemoryBarrierCount = 1, pImageMemoryBarriers = *imageBarrier };
    vkCmdPipelineBarrier2(cmdBuffer, *dependencies);
}

copy_image :: (cmdBuffer : VkCommandBuffer, srcImage : VkImage, srcExtent : VkExtent2D, dstImage : VkImage, dstExtent : VkExtent2D) {
    srcOffset := VkOffset3D.{ cast(s32) srcExtent.width, cast(s32) srcExtent.height, 1 };
    dstOffset := VkOffset3D.{ cast(s32) dstExtent.width, cast(s32) dstExtent.height, 1 };

    blitRegion := VkImageBlit2.{ .IMAGE_BLIT_2, null, .{ .COLOR_BIT, 0, 0, 1 }, .[ .{}, srcOffset ], .{ .COLOR_BIT, 0, 0, 1 }, .[ .{}, dstOffset ] };
    blitInfo := VkBlitImageInfo2.{ .BLIT_IMAGE_INFO_2, null, srcImage, .TRANSFER_SRC_OPTIMAL, dstImage, .TRANSFER_DST_OPTIMAL, 1, *blitRegion, .LINEAR };
    vkCmdBlitImage2(cmdBuffer, *blitInfo);
}

render_clear :: (cmdBuffer : VkCommandBuffer, image : VkImage, colour : Vector4) {
    clearValue : VkClearColorValue = .{_float32=colour.component};
    clearRange := make_image_subresource_range(.COLOR_BIT);
    vkCmdClearColorImage(cmdBuffer, image, .GENERAL, *clearValue, 1, *clearRange);
}

