/*
Project: Loam
File: bindless.glsl
Author: Brock Salmon
Created: 23AUG2025
*/

#extension GL_EXT_nonuniform_qualifier : require

layout (set = 0, binding = 0) uniform sampler2D textures[];

vec4 sampleTexture(uint id, vec2 uv) {
  return texture(nonuniformEXT(textures[id]), uv);
}
