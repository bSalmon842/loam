/*
Project: Loam
File: shared_layouts.glsl
Author: Brock Salmon
Created: 04JUN2025
*/

#extension GL_EXT_buffer_reference : require
#extension GL_EXT_nonuniform_qualifier : require
//#extension GL_EXT_debug_printf : enable

layout (set = 0, binding = 10) uniform sampler2D bindlessTextures[];

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
  uint textureIndex;
  VertexBuffer vertexBuffer;
};
