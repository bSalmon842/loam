/*
Project: Loam Engine
File: material.jai
Author: Brock Salmon
Created: 28AUG2026
*/

TextureWithFactor :: struct {
    texture : *ImageResource;
    factor  := Vector4.{1,1,1,1};
}

Material :: struct {
    name : string;
    
    baseColour    : TextureWithFactor;
    metalRough    : TextureWithFactor;
    emissive      : TextureWithFactor; // Factor is xyz, strength is w
    normalTexture : *ImageResource;

    isOpaque    : bool;
    alphaCutoff : float32;
}

GPUTextureWithFactor :: struct {
    factor       := Vector4.{1,1,1,1};
    textureIndex : s32;
    padding0 : s32;
    padding1 : s32;
    padding2 : s32;
} #no_padding;

GPUMaterial :: struct {
    baseColour : GPUTextureWithFactor;
    metalRough : GPUTextureWithFactor;
    emissive   : GPUTextureWithFactor; // xyz is factor, w is strength
    normalIndex : s32;
    isOpaque    : bool;
    alphaCutoff : float32;
} #no_padding;

to_gpu_tex_with_factor :: (texFactor : TextureWithFactor) -> GPUTextureWithFactor {
    return .{ texFactor.factor, ifx texFactor.texture then cast(s32) texFactor.texture.index else cast(s32)-1, 0, 0, 0 };
}

to_gpu_material :: (material : *Material) -> GPUMaterial {
    return .{
	to_gpu_tex_with_factor(material.baseColour),
	to_gpu_tex_with_factor(material.metalRough),
	to_gpu_tex_with_factor(material.emissive),
	ifx material.normalTexture then cast(s32)material.normalTexture.index else cast(s32)-1,
	material.isOpaque, material.alphaCutoff
    };
}


