/*
Project: Loam
File: vk/render_commands.jai
Author: Brock Salmon
Created: 23JUN2025
*/

RenderCommand :: struct {
    buffers : MeshBuffers;

    descriptorSet : VkDescriptorSet;
    indexCount : u32;

    pushConstants : AllPushConstants;
}

add_ui_render_command :: (elem : *UI_Element) {
    if #complete elem.type == {
	case .Empty; return;
	
	case .Text;   for elem.text.glyphs { add_render_command(.UI_Text, loam.uiCamera, *it.renderable, it.transform, elem.interact.hovered, elem.interact.hoverTint); }
	case .Sprite; add_render_command(.UI_Sprite, loam.uiCamera, *elem.sprite.renderable, elem.sprite.transform, elem.interact.hovered, elem.interact.hoverTint);
    }
}

add_render_command :: (pipelineType : PipelineType, camera : *Camera, renderable : *Renderable, transform : Transform,
		       useTintOverride : bool = false, tintOverride : Vector4 = DEFAULT_TEXTURE_TINT) {
    add_render_command_work(pipelineType, camera, renderable, transform, useTintOverride, tintOverride);
}

add_render_command_on_thread :: (pipeline : *RenderingPipelineInfo, renderCommand : *RenderCommand, camera : *Camera, renderable : *Renderable, transform : Transform,
				 useTintOverride : bool, tintOverride : Vector4) {
    // Save and reset the camera projection for after the command is made and use the pipeline's projection mode
    currentCameraProjection := camera.isOrthographic;
    camera.isOrthographic = pipeline.orthographic;
    
    // TODO: I think I suck at descriptors and this is leaking some memory until it hits some arbitrary point
    
    renderCommand.descriptorSet = dynamic_descriptor_pool_allocator_allocate(*vk.descriptorAllocator, vk.device, pipeline.descriptorLayout);
    writer : DescriptorWriter;
    defer clear_descriptor_writer(*writer);
    descriptor_write_image(*writer, 0, renderable.texture.image.view, .SHADER_READ_ONLY_OPTIMAL, vk.defaultSampler_Nearest, .COMBINED_IMAGE_SAMPLER);
    descriptor_writer_update_sets(*writer, vk.device, renderCommand.descriptorSet);
    
    renderCommand.pushConstants = .{ get_transform_matrix(transform, renderable.dimensions) * get_view_matrix(camera) * get_projection_matrix(camera),
				     ifx useTintOverride then tintOverride else renderable.tint, renderCommand.buffers.vertexBufferAddress };
    
    camera.isOrthographic = currentCameraProjection;
}

render_command :: (cmdBuffer : VkCommandBuffer, render : *RenderCommand, pipelineLayout : VkPipelineLayout) {
    vkCmdBindDescriptorSets(cmdBuffer, .GRAPHICS, pipelineLayout, 0, 1, *render.descriptorSet, 0, null);
    
    vkCmdPushConstants(cmdBuffer, pipelineLayout, .VERTEX_BIT, 0, size_of(AllPushConstants), *render.pushConstants);
    
    vkCmdBindIndexBuffer(cmdBuffer, render.buffers.indexBuffer.buffer, 0, .UINT32);
    vkCmdDrawIndexed(cmdBuffer, render.buffers.indexCount, 1, 0, 0, 0);
}

