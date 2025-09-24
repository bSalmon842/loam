/*
Project: Loam
File: bindless.glsl
Author: Brock Salmon
Created: 23AUG2025
*/

#extension GL_EXT_nonuniform_qualifier : require

layout (set = 0, binding = 0) uniform texture2D textures[];
layout (set = 0, binding = 1) uniform sampler   samplers[];

#define NEAREST_SAMPLER 0
#define LINEAR_SAMPLER  1

vec4 sampleTexture(uint id, uint samplerID, vec2 uv) {
  return texture(nonuniformEXT(sampler2D(textures[id], samplers[samplerID])), uv);
}
