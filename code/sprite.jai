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
    
    anim : SpriteAnimation;
}

SpriteAnimation :: struct {
    active      : bool;
    frameIndex  : s64;
    updateTimer : float64;

    FrameInfo :: struct {
	duration   : float64;
	uv0        : Vector2;
	uv1        : Vector2;
	dimensions : Vector2;
    }
    frames : [..] FrameInfo;
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

make_sprite :: (textureName : string, transform : Transform, spriteSheetJSON : string, startActive : bool = false, colour := DEFAULT_TEXTURE_TINT) -> *Sprite {
    sprite := New(Sprite);
    
    animInfo := get_resource(JSONResource, spriteSheetJSON);
    
    sprite.texture = get_resource(ImageResource, textureName);
    sprite.tint = colour;
    sprite.transform = transform;

    framesObject, framesFound := json_get_from_object(animInfo.json, "frames", .Object);
    if !framesFound then return null;
    
    spriteSheetDimensions := extent_to_vector(sprite.texture.image.extent);
    for framesObject.values {
	frame : SpriteAnimation.FrameInfo;

	frameObject, frameFound := json_get_from_object(it, "frame", .Object);
	if !frameFound then return null;
	
	// Get Frame Dimensions
	{
	    w, wFound := json_get_from_object(frameObject, "w", float64);
	    if !wFound then return null;
	    
	    h, hFound := json_get_from_object(frameObject, "h", float64);
	    if !hFound then return null;
	    
	    frame.dimensions = .{ cast(float) w, cast(float) h };
	}
	
	// Get Frame Duration
	{
	    frameDuration, found := json_get_from_object(it, "duration", float64);
	    if !found then return null;

	    frame.duration = frameDuration / 1000.0;
	}
	
	{
	    x, xFound := json_get_from_object(frameObject, "x", float64);
	    if !xFound then return null;
	    
	    y, yFound := json_get_from_object(frameObject, "y", float64);
	    if !yFound then return null;

	    framePosition := Vector2.{ cast(float) x, cast(float) y };
	    
	    frame.uv0 = framePosition / spriteSheetDimensions;
	    frame.uv1 = (framePosition + frame.dimensions) / spriteSheetDimensions;
	}

	array_add(*sprite.anim.frames, frame);
    }
    
    frame := sprite.anim.frames[sprite.anim.frameIndex];
    sprite.uv0 = frame.uv0;
    sprite.uv1 = frame.uv1;
    sprite.dimensions = frame.dimensions;
    
    sprite.anim.active = startActive;
    
    return sprite;
}

update_sprite_animation :: (sprite : *Sprite) {
    if sprite.anim.active {
	frame := sprite.anim.frames[sprite.anim.frameIndex];
	
	sprite.anim.updateTimer += loam.deltaTime;
	while sprite.anim.updateTimer > frame.duration {
	    sprite.anim.frameIndex += 1;
	    sprite.anim.updateTimer -= frame.duration;
	    if sprite.anim.frameIndex >= sprite.anim.frames.count {
		sprite.anim.frameIndex -= sprite.anim.frames.count;
	    }
	    
	    frame = sprite.anim.frames[sprite.anim.frameIndex];
	    sprite.uv0 = frame.uv0;
	    sprite.uv1 = frame.uv1;
	    sprite.dimensions = frame.dimensions;
	}
    }
}


