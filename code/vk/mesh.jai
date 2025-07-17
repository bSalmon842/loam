/*
Project: Loam
File: vk/mesh.jai
Author: Brock Salmon
Created: 20MAY2025
*/

Vertex :: struct {
    position : Vector3 #align 16;
    normal   : Vector3 #align 16;
    uv       : Vector2 #align 16;
    colour   := Vector4.{1,1,1,1} #align 16;
}

MeshBuffers :: struct {
    indexBuffer         : *AllocatedBufferInfo;
    indexCount          : u32;
    vertexBuffer        : *AllocatedBufferInfo;
    vertexBufferAddress : VkDeviceAddress;
}

MeshCopyData :: struct {
    vertexBufferSize : u64;
    indexBufferSize  : u64;
    stagingBuffer    : *AllocatedBufferInfo;
    buffers          : *MeshBuffers;
}

DEFAULT_PLANE_INDICES :: u32.[0, 1, 2,
		              2, 1, 3];
is_default_plane_indices :: (arr : [] u32) -> bool {
    if arr.count != DEFAULT_PLANE_INDICES.count then return false;
    for arr { if it != DEFAULT_PLANE_INDICES[it_index] then return false; }
    
    return true;
}

// TODO: (Per vkguide) Note that this pattern is not very efficient, as we are waiting for the GPU command to fully execute before continuing with our CPU side logic.
//                     This is something people generally put on a background thread, whose sole job is to execute uploads like this one, and deleting/reusing the staging buffers.
upload_mesh_threaded :: (loam : *LoamState, indices : [] u32, vertices : [] Vertex, buffers : *MeshBuffers) {
    vk := loam.vk;
    
    indexBufferSize := cast(u64) (indices.count * size_of(u32));
    vertexBufferSize := cast(u64) (vertices.count * size_of(Vertex));
    
    buffers.indexBuffer  = ifx is_default_plane_indices(indices) then vk.defaultPlaneIndexBuffer else create_vk_buffer(vk, indexBufferSize, .INDEX_BUFFER_BIT | .TRANSFER_DST_BIT, context.thread_index);
    buffers.indexCount   = cast(u32) indices.count;
    
    buffers.vertexBuffer = create_vk_buffer(vk, vertexBufferSize, .STORAGE_BUFFER_BIT | .TRANSFER_DST_BIT | .SHADER_DEVICE_ADDRESS_BIT, context.thread_index);
    deviceAddressInfo := VkBufferDeviceAddressInfo.{ .BUFFER_DEVICE_ADDRESS_INFO, null, buffers.vertexBuffer.buffer };
    buffers.vertexBufferAddress = vkGetBufferDeviceAddress(vk.device, *deviceAddressInfo);
    
    // Set up staging buffer and copy to buffers
    stagingBuffer := create_vk_buffer(vk, indexBufferSize + vertexBufferSize, .TRANSFER_SRC_BIT, context.thread_index);
    defer destroy_vk_buffer(vk, stagingBuffer);
    
    memcpy(stagingBuffer.allocationInfo.pMappedData, cast(*u8) vertices.data, cast(s64) vertexBufferSize);
    memcpy(cast(*u8) stagingBuffer.allocationInfo.pMappedData + vertexBufferSize, cast(*u8) indices.data, cast(s64) indexBufferSize);

    gpu_mesh_copy :: (cmdBuffer : VkCommandBuffer, data : *void) {
	meshData := cast(*MeshCopyData) data;

	vertexCopy := VkBufferCopy.{ 0, 0, meshData.vertexBufferSize };
	vkCmdCopyBuffer(cmdBuffer, meshData.stagingBuffer.buffer, meshData.buffers.vertexBuffer.buffer, 1, *vertexCopy);
	
	indexCopy := VkBufferCopy.{ meshData.vertexBufferSize, 0, meshData.indexBufferSize };
	vkCmdCopyBuffer(cmdBuffer, meshData.stagingBuffer.buffer, meshData.buffers.indexBuffer.buffer, 1, *indexCopy);
    }

    meshData := MeshCopyData.{ vertexBufferSize, indexBufferSize, stagingBuffer, buffers };
    immediate_submit(vk, gpu_mesh_copy, *meshData);
}
