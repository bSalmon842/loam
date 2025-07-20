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

add_ui_render_command :: (loam : *LoamState, elem : *UI_Element) {
    if #complete elem.type == {
	case .Empty; return;
	
	case .Text;   add_render_command(loam, .UI_Text, loam.uiCamera, *elem.text.renderable, elem.text.transform, elem.interact.hovered, elem.interact.hoverTint);
	case .Sprite; add_render_command(loam, .UI_Sprite, loam.uiCamera, *elem.sprite.renderable, elem.sprite.transform, elem.interact.hovered, elem.interact.hoverTint);
    }
}

add_render_command :: (loam : *LoamState, pipelineType : PipelineType, camera : *Camera, renderable : *Renderable, transform : Transform,
		       useTintOverride : bool = false, tintOverride : Vector4 = DEFAULT_TEXTURE_TINT) {
    add_render_command_threaded(loam, pipelineType, camera, renderable, transform, useTintOverride, tintOverride);
    /*
    threadWork : ThreadWork;
    threadWork.type = .AddRenderCommand;
    threadWork.loam = loam;
    threadWork.renderCommandData = .{ pipelineType, camera, renderable, transform, useTintOverride, tintOverride, add_render_command_threaded };
    add_thread_work(*loam.threadSystem, threadWork, "Add Render Command");
*/
}

add_render_command_threaded :: (loam : *LoamState, pipelineType : PipelineType, camera : *Camera, renderable : *Renderable, transform : Transform,
		       useTintOverride : bool, tintOverride : Vector4) {
    if !renderable.buffers then return;
    
    pipeline := *loam.vk.pipelines[pipelineType];

    // Save and reset the camera projection for after the command is made and use the pipeline's projection mode
    currentCameraProjection := camera.isOrthographic;
    camera.isOrthographic = pipeline.orthographic;
    
    renderCommand : RenderCommand;
    renderCommand.buffers = renderable.buffers;

    // TODO: I think I suck at descriptors and this is leaking some memory until it hits some arbitrary point
    renderCommand.descriptorSet = dynamic_descriptor_pool_allocator_allocate(*loam.vk.descriptorAllocator, loam.vk.device, pipeline.descriptorLayout);
    writer : DescriptorWriter;
    defer clear_descriptor_writer(*writer);
    descriptor_write_image(*writer, 0, renderable.texture.view, .SHADER_READ_ONLY_OPTIMAL, loam.vk.defaultSampler_Nearest, .COMBINED_IMAGE_SAMPLER);
    descriptor_writer_update_sets(*writer, loam.vk.device, renderCommand.descriptorSet);

    renderCommand.pushConstants = .{ get_transform_matrix(transform, renderable.dimensions) * get_view_matrix(camera) * get_projection_matrix(camera),
				     ifx useTintOverride then tintOverride else renderable.tint, renderCommand.buffers.vertexBufferAddress };

    camera.isOrthographic = currentCameraProjection;
    array_add(*pipeline.renderCommands, renderCommand);
}

render_command :: (vk : *Vk, cmdBuffer : VkCommandBuffer, render : *RenderCommand, pipelineLayout : VkPipelineLayout) {
    vkCmdBindDescriptorSets(cmdBuffer, .GRAPHICS, pipelineLayout, 0, 1, *render.descriptorSet, 0, null);
    
    vkCmdPushConstants(cmdBuffer, pipelineLayout, .VERTEX_BIT, 0, size_of(AllPushConstants), *render.pushConstants);
    
    vkCmdBindIndexBuffer(cmdBuffer, render.buffers.indexBuffer.buffer, 0, .UINT32);
    vkCmdDrawIndexed(cmdBuffer, render.buffers.indexCount, 1, 0, 0, 0);
}

