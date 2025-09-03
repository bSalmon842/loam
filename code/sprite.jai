/*
Project: Loam
File: sprite.jai
Author: Brock Salmon
Created: 04JUL2025
*/

MAX_SPRITES : u32 : 1024;

Sprite :: struct {
    using transform : Transform;
    using renderable : Renderable2D;
}

GPUSpriteInfo :: struct {
    transform  : Matrix4;
    colour     : Vector4;
    uv0        : Vector2;
    uv1        : Vector2;
    dimensions : Vector2;
    textureID  : u32;
    padding    : u32;
}

make_sprite :: (textureName : string, transform : Transform, colour := DEFAULT_TEXTURE_TINT) -> *Sprite {
    sprite := New(Sprite);
    
    sprite.texture = get_resource(ImageResource, textureName);
    sprite.tint = colour;
    sprite.dimensions = extent_to_vector(sprite.texture.image.extent);
    sprite.transform = transform;
    
    return sprite;
}



