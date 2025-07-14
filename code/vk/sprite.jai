/*
Project: Loam
File: sprite.jai
Author: Brock Salmon
Created: 04JUL2025
*/

Sprite :: struct {
    colour : Vector4 = DEFAULT_TEXTURE_TINT;
    using transform : Transform;
    using renderable : Renderable2D;
}

make_sprite :: (loam : *LoamState, textureName : string, transform : Transform, colour := DEFAULT_TEXTURE_TINT) -> *Sprite {
    sprite := New(Sprite);
    
    textureAsset := request_asset(loam, .Image, textureName);
    if textureAsset {
	sprite.texture = create_vk_image_from_ktx(loam.vk, cast(*ktxTexture2) textureAsset.data);
    } else {
	sprite.texture = loam.vk.errorCheckerboard;
    }

    sprite.colour = colour;
    sprite.transform = transform;

    sprite.vertices, sprite.vertexMemory = build_sprite_buffers(loam.vk, sprite);
    sprite.buffers = New(MeshBuffers);

    threadWork : ThreadWork;
    threadWork.type = .UploadToGPU;
    threadWork.loam = loam;
    threadWork.uploadData = .{ DEFAULT_PLANE_INDICES, sprite.vertices, sprite.buffers, upload_mesh_threaded };
    add_thread_work(*loam.threadSystem, threadWork, "Upload new Sprite to GPU");
    
    return sprite;
}

build_sprite_buffers :: (vk : *Vk, sprite : *Sprite) -> [] Vertex, *void {
    sprite.dimensions = extent_to_vector(sprite.texture.extent);
    
    // Build info to upload to GPU
    vertices, vertexMemory := NewArray(4, Vertex);
    vertices[0] = .{ position=.{ sprite.dimensions.x, 0,                   0 }, uv=.{ 1, 1 } };
    vertices[1] = .{ position=.{ sprite.dimensions.x, sprite.dimensions.y, 0 }, uv=.{ 1, 0 } };
    vertices[2] = .{ position=.{ 0,                   0,                   0 }, uv=.{ 0, 1 } };
    vertices[3] = .{ position=.{ 0,                   sprite.dimensions.y, 0 }, uv=.{ 0, 0 } };

    return vertices, vertexMemory;
}



