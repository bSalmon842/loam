/*
Project: Loam
File: box_collider_vertex.glsl
Author: Brock Salmon
Created: 09APR2026
*/

#version 460
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require

layout (location = 0) out vec4 outColour;

// Sprite Info
struct ColliderInfo {
  mat4 transform;
  vec4 colour;
  vec3 dimensions;
  uint padding;
};

layout (buffer_reference, scalar) readonly buffer ColliderInfoBuffer {
  ColliderInfo colliderInfos[];
};

struct ColliderPushConstants {
  mat4 viewProj;
  ColliderInfoBuffer colliderBuffer;
};

const vec3 CUBE_BASE_VERTICES[] = { { 0, 0, 1 }, { 1, 0, 1 }, { 0, 1, 1 }, { 1, 1, 1 },
				    { 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 } };

layout (push_constant) uniform constants {
  ColliderPushConstants pc;
} PushConstants;

void main() {
  ColliderInfo collider = PushConstants.pc.colliderBuffer.colliderInfos[gl_InstanceIndex];

  vec3 vertexPosition = CUBE_BASE_VERTICES[gl_VertexIndex] * collider.dimensions;
  gl_Position = (PushConstants.pc.viewProj * collider.transform) * vec4(vertexPosition, 1.0f);

  outColour = collider.colour;
}

