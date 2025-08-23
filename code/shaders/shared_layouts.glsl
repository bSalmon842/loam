/*
Project: Loam
File: shared_layouts.glsl
Author: Brock Salmon
Created: 04JUN2025
*/

#extension GL_EXT_buffer_reference : require
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
