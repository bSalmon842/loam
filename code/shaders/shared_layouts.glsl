/*
Project: Loam
File: shared_layouts.glsl
Author: Brock Salmon
Created: 04JUN2025
*/

#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_GOOGLE_include_directive : require
//#extension GL_EXT_debug_printf : enable

#include "bindless.glsl"

struct VertexInfo {
  vec3 position;
  vec3 normal;
  vec2 uv;
  vec4 colour;
};

layout (buffer_reference, std430) readonly buffer VertexBuffer {
    VertexInfo vertices[];
};

struct CommonPushConstants {
  mat4 renderMatrix;
  vec4 colour;
  uint textureID;
  VertexBuffer vertexBuffer;
};

// Sprite Info
struct SpriteInfo {
  mat4 transform;
  vec4 colour;
  vec2 uv0;
  vec2 uv1;
  vec2 dimensions;
  uint textureID;
  uint padding;
};

layout (buffer_reference, scalar) readonly buffer SpriteInfoBuffer {
  SpriteInfo spriteInfos[];
};

struct SpritePushConstants {
  mat4 viewProj;
  SpriteInfoBuffer spriteBuffer;
};

// Store the 6 uvs for a basic sprite so we don't need to 
const vec2 SPRITE_BASE_UVS[] = { { 1, 1 }, { 1, 0 }, { 0, 1 }, { 0, 1 }, { 1, 0 }, { 0, 0 } };
const vec2 SPRITE_BASE_POSITIONS[] = { { 1, 0 }, { 1, 1 }, { 0, 0 }, { 0, 0 }, { 1, 1 }, { 0, 1 } };
