/*
Project: Loam
File: render.jai
Author: Brock Salmon
Created: 17MAY2025
*/

get_current_frame :: (vk : *Vk) -> *FrameCommandInfo #must {
    return *vk.frames[vk.currentFrame % FRAMES_IN_FLIGHT];
}

draw_frame :: (loam : *LoamState) {
    vk := loam.vk;
    currentFrame := get_current_frame(vk);

    check_vk(vkWaitForFences(vk.device, 1, *currentFrame.renderFence, VK_TRUE, seconds_to_nanoseconds(1)), "vkWaitForFences failed");
    check_vk(vkResetFences(vk.device, 1, *currentFrame.renderFence), "vkWaitForFences failed");

    dynamic_descriptor_pool_allocator_reset_pools(*currentFrame.descriptors, vk.device);

    swapchainImageIndex : u32;
    acquireResult := vkAcquireNextImageKHR(vk.device, vk.swapchain, seconds_to_nanoseconds(1), currentFrame.swapSemaphore, null, *swapchainImageIndex);
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

    cmdBuffer := currentFrame.cmdBuffer;
    check_vk(vkResetCommandBuffer(cmdBuffer, 0), tprint("Failed to reset Command Buffer for frame %", vk.currentFrame));

    cmdBufferBeginInfo := VkCommandBufferBeginInfo.{ .COMMAND_BUFFER_BEGIN_INFO, null, .ONE_TIME_SUBMIT_BIT, null };
    check_vk(vkBeginCommandBuffer(cmdBuffer, *cmdBufferBeginInfo), tprint("Failed to begin Command Buffer for frame %", vk.currentFrame));

    transition_image(cmdBuffer, vk.drawImage.image, .UNDEFINED, .GENERAL);

    render_clear(cmdBuffer, vk.drawImage.image, .{0.2, 0.2, 0.2, 1.0});
    
    transition_image(cmdBuffer, vk.drawImage.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL);

    // Draw Triangle Shader
    {
	colourAttachment := make_rendering_attachment_info(vk.drawImage.view, layout=.GENERAL);
	renderInfo := make_rendering_info(drawExtent, *colourAttachment, null);

	vkCmdBeginRendering(cmdBuffer, *renderInfo);
	vkCmdBindPipeline(cmdBuffer, .GRAPHICS, vk.meshPipeline);

	viewport := VkViewport.{ width = cast(float) drawExtent.width, height = cast(float) drawExtent.height, minDepth = 0, maxDepth = 1 };
	vkCmdSetViewport(cmdBuffer, 0, 1, *viewport);

	scissor := VkRect2D.{ .{}, drawExtent };
	vkCmdSetScissor(cmdBuffer, 0, 1, *scissor);
	
	imageSet := dynamic_descriptor_pool_allocator_allocate(*currentFrame.descriptors, vk.device, vk.singleTextureDescriptorLayout);
	writer : DescriptorWriter;
	defer clear_descriptor_writer(*writer);
	descriptor_write_image(*writer, 0, vk.testTexture.view, .SHADER_READ_ONLY_OPTIMAL, vk.defaultSampler_Nearest, .COMBINED_IMAGE_SAMPLER);
	descriptor_writer_update_sets(*writer, vk.device, imageSet);

	vkCmdBindDescriptorSets(cmdBuffer, .GRAPHICS, vk.meshPipelineLayout, 0, 1, *imageSet, 0, null );

	pushConstants := MeshPushConstants.{ get_view_matrix(loam.camera) * get_projection_matrix(loam.camera), vk.testRect.vertexBufferAddress };
	vkCmdPushConstants(cmdBuffer, vk.meshPipelineLayout, .VERTEX_BIT, 0, size_of(MeshPushConstants), *pushConstants );

	vkCmdBindIndexBuffer(cmdBuffer, vk.testRect.indexBuffer.buffer, 0, .UINT32);
	vkCmdDrawIndexed(cmdBuffer, 6, 1, 0, 0, 0);
	
	vkCmdEndRendering(cmdBuffer);
    }
    
    
    transition_image(cmdBuffer, vk.drawImage.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL);
    transition_image(cmdBuffer, currentSwapchainImage, .UNDEFINED, .TRANSFER_DST_OPTIMAL);

    copy_image(cmdBuffer, vk.drawImage.image, drawExtent, currentSwapchainImage, vk.swapchainExtent);

    transition_image(cmdBuffer, currentSwapchainImage, .TRANSFER_DST_OPTIMAL, .PRESENT_SRC_KHR);
    
    check_vk(vkEndCommandBuffer(cmdBuffer), tprint("Failed to end Command Buffer for frame %", vk.currentFrame));

    // Submit Command Buffer to Queue
    cmdInfo := VkCommandBufferSubmitInfo.{ commandBuffer=cmdBuffer };
    waitInfo := make_semaphore_submit_info(currentFrame.swapSemaphore, .COLOR_ATTACHMENT_OUTPUT_BIT);
    signalInfo := make_semaphore_submit_info(currentFrame.renderSemaphore, .ALL_GRAPHICS_BIT);
    submitInfo := VkSubmitInfo2.{ .SUBMIT_INFO_2, null, 0, 1, *waitInfo, 1, *cmdInfo, 1, *signalInfo };
    check_vk(vkQueueSubmit2(vk.graphicsQueue, 1, *submitInfo, currentFrame.renderFence), tprint("Failed to submit Queue for frame %", vk.currentFrame));

    // Present Queue
    presentInfo := VkPresentInfoKHR.{ .PRESENT_INFO_KHR, null, 1, *currentFrame.renderSemaphore, 1, *vk.swapchain, *swapchainImageIndex, null };
    presentResult := vkQueuePresentKHR(vk.graphicsQueue, *presentInfo);
    if presentResult == .ERROR_OUT_OF_DATE_KHR {
	vk.resizeRequested = true;
        log(.INFO, "Vulkan has requested a resize from vkQueuePresentKHR");
	return;
    } else if presentResult != .SUBOPTIMAL_KHR {
	check_vk(presentResult, tprint("Failed to present queue for frame %", vk.currentFrame));
    }
    
    vk.currentFrame += 1;
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

// Render Commands
render_clear :: (cmdBuffer : VkCommandBuffer, image : VkImage, colour : Vector4) {
    clearValue : VkClearColorValue = .{_float32=colour.component};
    clearRange := make_image_subresource_range(.COLOR_BIT);
    vkCmdClearColorImage(cmdBuffer, image, .GENERAL, *clearValue, 1, *clearRange);
}
