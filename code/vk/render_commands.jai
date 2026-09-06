/*
Project: Loam
File: vk/render_commands.jai
Author: Brock Salmon
Created: 23JUN2025
*/

MeshRenderCommand :: struct {
    buffers : *GPUBuffers;
    vertexPushConstants : VertexMeshPushConstants;
    fragmentPushConstants : FragmentMeshPushConstants;
}

add_ui_render_command :: (elem : *UI_Element) {
    if #complete elem.type == {
	case .Empty; return;
	
	case .Text;   for elem.text.glyphs { add_sprite_render_command(.UI_Text, it.renderable, it.transform); }
	case .Sprite; add_sprite_render_command(.UI_Sprite, elem.sprite.renderable, elem.sprite.transform);
    }
}

add_render_command :: (pipelineType : PipelineType, camera : *Camera, renderable : *Renderable, transform : Transform) {
    if !renderable.buffers.indexBuffer then return;
    
    pipeline := *vk.pipelines[pipelineType];
    
    render := New(MeshRenderCommand);
    found := false;
    for * pipeline.renderCommands {
	if !it.* {
	    it.* = render;
	    found = true;
	    break;
	}
    }
    if !found {
	log(.ERROR, "Render Command array is full");
	free(render);
	return;
    }

    render.buffers = renderable.buffers;
    
    // Save and reset the camera projection for after the command is made and use the pipeline's projection mode
    currentCameraProjection := camera.isOrthographic;
    camera.isOrthographic = pipeline.orthographic;
    
    tranMatrix := get_transform_matrix(transform, .{1,1,1});
    render.vertexPushConstants = .{ tranMatrix, render.buffers.vertex.bufferAddress, 0 };
    render.fragmentPushConstants = .{ to_gpu_material(renderable.material) };
    
    camera.isOrthographic = currentCameraProjection;
}

add_sprite_render_command :: (pipelineType : PipelineType, renderable : Renderable2D, transform : Transform) {
    pipeline := *vk.pipelines[pipelineType];
    if pipeline.sprites.count == MAX_SPRITES then return;

    spriteInfo := GPUSpriteInfo.{
	get_transform_matrix(transform, renderable.dimensions),	renderable.tint, renderable.uv0, renderable.uv1, renderable.dimensions, renderable.texture.index, 0
    };

    pipeline.sprites.array[pipeline.sprites.count] = spriteInfo;
    pipeline.sprites.count += 1;
}

// TODO: Change this to use a draw context for transparent and opaque objects?
// TODO: This also can't really be used long term as we might want different parts of the model rendered with different pipelines
add_model_render_command :: (pipelineType : PipelineType, model : *Model) {
    if model.active then add_render_commands_for_model_nodes(model.nodes, pipelineType, model);
}

add_render_commands_for_model_nodes :: (nodes : ModelNodeList, pipelineType : PipelineType, model : *Model) {
    for node : nodes {
	if node.active {
	    if node.node.meshIndex != -1 {
		mesh := model.resource.gltf.meshes[node.node.meshIndex];
		for mesh.prims {
		    if it.active {
			// TODO: The transform is screwed here due to world/local issues
			add_render_command(pipelineType, loam.activeGameCamera, *it.renderable, model.transform);//alter_transform(node.node.worldTransform, model.transform));
		    }
		}
	    }

	    add_render_commands_for_model_nodes(node.children, pipelineType, model);
	}
    }
}

add_rect_render_command :: (dimensions : Vector2, transform : Transform, colour : Vector4) {
    pipeline := *vk.pipelines[PipelineType.Sprite_Rect];
    if pipeline.sprites.count == MAX_SPRITES then return;

    spriteInfo := GPUSpriteInfo.{
	get_transform_matrix(transform, dimensions),
	colour, .{}, .{},
	dimensions, 0, 0
    };

    pipeline.sprites.array[pipeline.sprites.count] = spriteInfo;
    pipeline.sprites.count += 1;
}

render_command :: (cmdBuffer : VkCommandBuffer, render : *MeshRenderCommand, pipelineLayout : VkPipelineLayout) {
    vkCmdPushConstants(cmdBuffer, pipelineLayout, .VERTEX_BIT, 0,                                size_of(VertexMeshPushConstants), *render.vertexPushConstants);
    vkCmdPushConstants(cmdBuffer, pipelineLayout, .FRAGMENT_BIT, size_of(VertexMeshPushConstants), size_of(FragmentMeshPushConstants), *render.fragmentPushConstants);
    
    vkCmdBindIndexBuffer(cmdBuffer, render.buffers.indexBuffer.buffer, 0, .UINT32);
    vkCmdDrawIndexed(cmdBuffer, render.buffers.indexCount, 1, 0, 0, 0);
}

render_sprite_batch :: (cmdBuffer : VkCommandBuffer, pushConstants : SpritePushConstants, spriteCount : u32, pipelineLayout : VkPipelineLayout) {
    vkCmdPushConstants(cmdBuffer, pipelineLayout, .VERTEX_BIT, 0, size_of(SpritePushConstants), *pushConstants);
    
    vkCmdBindIndexBuffer(cmdBuffer, vk.defaultPlaneIndexBuffer.buffer, 0, .UINT32);
    vkCmdDrawIndexed(cmdBuffer, DEFAULT_PLANE_INDICES.count, spriteCount, 0, 0, 0);
}

#if IS_DEV {
    add_box_collider_render_command :: (dimensions : Vector3, transform : Transform, collided : bool) {
	pipeline := *vk.pipelines[PipelineType.Colliders_Box];
	if pipeline.boxColliders.count == MAX_VISIBLE_COLLIDERS then return;

	colliderInfo := GPUBoxColliderInfo.{
	    get_transform_matrix(transform, dimensions),
	    ifx collided then Vector4.{ 1, 0, 0, 1 } else Vector4.{ 0, 1, 1, 1 },
	    dimensions, 0
	};

	pipeline.boxColliders.array[pipeline.boxColliders.count] = colliderInfo;
	pipeline.boxColliders.count += 1;
    }

    render_box_collider_batch :: (cmdBuffer : VkCommandBuffer, pushConstants : BoxColliderPushConstants, colliderCount : u32, pipelineLayout : VkPipelineLayout) {
	vkCmdPushConstants(cmdBuffer, pipelineLayout, .VERTEX_BIT, 0, size_of(BoxColliderPushConstants), *pushConstants);
	
	vkCmdBindIndexBuffer(cmdBuffer, vk.defaultCubeIndexBuffer.buffer, 0, .UINT32);
	vkCmdDrawIndexed(cmdBuffer, DEFAULT_CUBE_INDICES.count, colliderCount, 0, 0, 0);
    }
}
