/*
Project: Loam
File: sprite.jai
Author: Brock Salmon
Created: 04JUL2025
*/

Sprite :: struct {
    using transform : Transform;
    using renderable : Renderable;
}

make_sprite :: (textureName : string, transform : Transform, colour := DEFAULT_TEXTURE_TINT) -> *Sprite {
    sprite := New(Sprite);
    
    sprite.texture = get_resource(ImageResource, textureName);
    sprite.tint = colour;
    sprite.transform = transform;

    sprite.vertices, sprite.vertexMemory = build_sprite_buffers(sprite);
    sprite.buffers = New(MeshBuffers);
    
    upload_mesh_command(DEFAULT_PLANE_INDICES, sprite.vertices, sprite.buffers);
    
    return sprite;
}

build_sprite_buffers :: (sprite : *Sprite) -> [] Vertex, *void {
    sprite.dimensions = extent_to_vector(sprite.texture.image.extent, 0);
    
    // Build info to upload to GPU
    vertices, vertexMemory := NewArray(4, Vertex);
    vertices[0] = .{ position=.{ sprite.dimensions.x, 0,                   0 }, uv=.{ 1, 1 } };
    vertices[1] = .{ position=.{ sprite.dimensions.x, sprite.dimensions.y, 0 }, uv=.{ 1, 0 } };
    vertices[2] = .{ position=.{ 0,                   0,                   0 }, uv=.{ 0, 1 } };
    vertices[3] = .{ position=.{ 0,                   sprite.dimensions.y, 0 }, uv=.{ 0, 0 } };

    return vertices, vertexMemory;
}



