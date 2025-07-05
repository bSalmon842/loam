/*
Project: Loam
File: sprite.jai
Author: Brock Salmon
Created: 04JUL2025
*/

Sprite :: struct {
    texture : *AllocatedImageInfo;

    colour : Vector4 = DEFAULT_TEXTURE_TINT;
    using transform : Transform;
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

    return sprite;
}

build_sprite_buffers :: (vk : *Vk, sprite : *Sprite) -> [] Vertex {
    dimensions := extent_to_vector(sprite.texture.extent);
    
    // Build info to upload to GPU
    vertices := NewArray(4, Vertex,, temp);
    vertices[0] = .{ position=.{ dimensions.x, 0,            0 }, uv=.{ 1, 1 } };
    vertices[1] = .{ position=.{ dimensions.x, dimensions.y, 0 }, uv=.{ 1, 0 } };
    vertices[2] = .{ position=.{ 0,            0,            0 }, uv=.{ 0, 1 } };
    vertices[3] = .{ position=.{ 0,            dimensions.y, 0 }, uv=.{ 0, 0 } };

    return vertices;
}



