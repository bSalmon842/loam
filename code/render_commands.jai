/*
Project: Loam
File: vk/render_commands.jai
Author: Brock Salmon
Created: 23JUN2025
*/

/* Game Rendering
draw_sprite :: ();
draw_mesh :: ();
*/

/* UI
draw_ui_text :: ();
draw_ui_image :: ();
draw_ui_button :: ();
*/

RenderCommand :: struct {
    pipeline       : VkPipeline;
    pipelineLayout : VkPipelineLayout;

    buffers : MeshBuffers;
    drawImage : *AllocatedImageInfo;

    descriptorSet : VkDescriptorSet;
    indexCount : u32;

    pushConstants : MeshPushConstants;
}

draw_ui_text :: (loam : *LoamState, text : *Text) {
    //vkDeviceWaitIdle(loam.vk.device);
    
    renderCommand : RenderCommand;
    renderCommand.pipeline = loam.vk.uiPipeline.textPipeline;
    renderCommand.pipelineLayout = loam.vk.uiPipeline.layout;
    
    vertices, stringTexture := build_text(loam.vk, text);
    buffers := upload_mesh(loam.vk, DEFAULT_PLANE_INDICES, vertices);
    renderCommand.buffers = buffers;
    renderCommand.drawImage = loam.vk.drawImage;

    // TODO: I think I suck at descriptors and this is leaking some memory until it hits some arbitrary point
    renderCommand.descriptorSet = dynamic_descriptor_pool_allocator_allocate(*loam.vk.descriptorAllocator, loam.vk.device, loam.vk.uiPipeline.uiDescriptorLayout);
    writer : DescriptorWriter;
    defer clear_descriptor_writer(*writer);
    descriptor_write_image(*writer, 0, stringTexture.view, .SHADER_READ_ONLY_OPTIMAL, loam.vk.defaultSampler_Nearest, .COMBINED_IMAGE_SAMPLER);
    descriptor_writer_update_sets(*writer, loam.vk.device, renderCommand.descriptorSet);
    
    array_add(*loam.vk.imagesToDestroyAtFrameReset, stringTexture);
    array_add(*loam.vk.buffersToDestroyAtFrameReset, buffers.vertexBuffer);
    
    // NOTE: For UI elements we save the old projection mode, render with orthographic, then return to the old projection mode
    oldProjectionMode := loam.camera.isOrthographic;
    loam.camera.isOrthographic = true;
    textureDims := Vector3.{ cast(float) stringTexture.extent.width, cast(float) stringTexture.extent.height, 0 };
    renderCommand.pushConstants = .{ get_transform_matrix(text.transform, textureDims) * get_view_matrix(loam.camera) * get_projection_matrix(loam.camera),
				     renderCommand.buffers.vertexBufferAddress };
    loam.camera.isOrthographic = oldProjectionMode;
    
    array_add(*loam.renderCommands, renderCommand);
}

render_command :: (vk : *Vk, cmdBuffer : VkCommandBuffer, render : *RenderCommand) {
    //vkDeviceWaitIdle(loam.vk.device);
    
    vkCmdBindPipeline(cmdBuffer, .GRAPHICS, render.pipeline);

    colourAttachment := make_rendering_attachment_info(render.drawImage.view, layout=.GENERAL);
    renderInfo := make_rendering_info(render.drawImage.extent, *colourAttachment, null);
    vkCmdBeginRendering(cmdBuffer, *renderInfo);

    viewport := VkViewport.{ width = cast(float) render.drawImage.extent.width, height = cast(float) render.drawImage.extent.height, minDepth = 0, maxDepth = 1 };
    vkCmdSetViewport(cmdBuffer, 0, 1, *viewport);
    
    scissor := VkRect2D.{ .{}, render.drawImage.extent };
    vkCmdSetScissor(cmdBuffer, 0, 1, *scissor);

    vkCmdBindDescriptorSets(cmdBuffer, .GRAPHICS, render.pipelineLayout, 0, 1, *render.descriptorSet, 0, null);
    
    vkCmdPushConstants(cmdBuffer, render.pipelineLayout, .VERTEX_BIT, 0, size_of(MeshPushConstants), *render.pushConstants);
    
    vkCmdBindIndexBuffer(cmdBuffer, render.buffers.indexBuffer.buffer, 0, .UINT32);
    vkCmdDrawIndexed(cmdBuffer, render.buffers.indexCount, 1, 0, 0, 0);
    
    vkCmdEndRendering(cmdBuffer);
}

