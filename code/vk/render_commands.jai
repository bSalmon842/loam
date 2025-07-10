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
draw_ui_element :: (); // Draws text and image
draw_ui_text :: ();
draw_ui_image :: ();
draw_ui_button :: ();
*/

RenderCommand :: struct {
    buffers : MeshBuffers;

    descriptorSet : VkDescriptorSet;
    indexCount : u32;

    pushConstants : AllPushConstants;
}

draw_ui_element :: (loam : *LoamState, elem : *UI_Element) {
    if #complete elem.type == {
	case .Empty; return;
	
	case .Text; {
	    draw_ui_text(loam, elem.text, ifx elem.interact.hovered then elem.interact.hoverTint else elem.text.colour);
	}

	case .Image; Invalid_Codepath();
    }
}

draw_ui_text :: (loam : *LoamState, text : *Text, colour : Vector4) {
    pipeline := *loam.vk.pipelines[PipelineTypes.UI_Text];
    
    renderCommand : RenderCommand;

    buffers := upload_mesh(loam.vk, DEFAULT_PLANE_INDICES, text.vertices);
    renderCommand.buffers = buffers;

    // TODO: I think I suck at descriptors and this is leaking some memory until it hits some arbitrary point
    renderCommand.descriptorSet = dynamic_descriptor_pool_allocator_allocate(*loam.vk.descriptorAllocator, loam.vk.device, pipeline.descriptorLayout);
    writer : DescriptorWriter;
    defer clear_descriptor_writer(*writer);
    descriptor_write_image(*writer, 0, text.texture.view, .SHADER_READ_ONLY_OPTIMAL, loam.vk.defaultSampler_Nearest, .COMBINED_IMAGE_SAMPLER);
    descriptor_writer_update_sets(*writer, loam.vk.device, renderCommand.descriptorSet);
    
    array_add(*loam.vk.buffersToDestroyAtFrameReset, buffers.vertexBuffer);
    
    // NOTE: For UI elements we save the old projection mode, render with orthographic, then return to the old projection mode
    textureDims := Vector3.{ text.dimensions.x, text.dimensions.y, 0 };
    renderCommand.pushConstants = .{ get_transform_matrix(text.transform, textureDims) * get_view_matrix(loam.uiCamera) * get_projection_matrix(loam.uiCamera), colour,
				     renderCommand.buffers.vertexBufferAddress };
    
    array_add(*pipeline.renderCommands, renderCommand);
}

draw_sprite :: (loam : *LoamState, sprite : *Sprite) {
    pipeline := *loam.vk.pipelines[PipelineTypes.Sprite];
    
    renderCommand : RenderCommand;
    
    buffers := upload_mesh(loam.vk, DEFAULT_PLANE_INDICES, sprite.vertices);
    renderCommand.buffers = buffers;

    // TODO: I think I suck at descriptors and this is leaking some memory until it hits some arbitrary point
    renderCommand.descriptorSet = dynamic_descriptor_pool_allocator_allocate(*loam.vk.descriptorAllocator, loam.vk.device, pipeline.descriptorLayout);
    writer : DescriptorWriter;
    defer clear_descriptor_writer(*writer);
    descriptor_write_image(*writer, 0, sprite.texture.view, .SHADER_READ_ONLY_OPTIMAL, loam.vk.defaultSampler_Nearest, .COMBINED_IMAGE_SAMPLER);
    descriptor_writer_update_sets(*writer, loam.vk.device, renderCommand.descriptorSet);
    
    array_add(*loam.vk.buffersToDestroyAtFrameReset, buffers.vertexBuffer);
    
    // NOTE: For UI elements we save the old projection mode, render with orthographic, then return to the old projection mode
    oldProjectionMode := loam.sceneCamera.isOrthographic;
    loam.sceneCamera.isOrthographic = true;
    textureDims := extent_to_vector(sprite.texture.extent, 0 );
    renderCommand.pushConstants = .{ get_transform_matrix(sprite.transform, textureDims) * get_view_matrix(loam.sceneCamera) * get_projection_matrix(loam.sceneCamera),
				     sprite.colour, renderCommand.buffers.vertexBufferAddress };
    loam.sceneCamera.isOrthographic = oldProjectionMode;
    
    array_add(*pipeline.renderCommands, renderCommand);
}

render_command :: (vk : *Vk, cmdBuffer : VkCommandBuffer, render : *RenderCommand, pipelineLayout : VkPipelineLayout) {
    vkCmdBindDescriptorSets(cmdBuffer, .GRAPHICS, pipelineLayout, 0, 1, *render.descriptorSet, 0, null);
    
    vkCmdPushConstants(cmdBuffer, pipelineLayout, .VERTEX_BIT, 0, size_of(AllPushConstants), *render.pushConstants);
    
    vkCmdBindIndexBuffer(cmdBuffer, render.buffers.indexBuffer.buffer, 0, .UINT32);
    vkCmdDrawIndexed(cmdBuffer, render.buffers.indexCount, 1, 0, 0, 0);
}

