/*
Project: Loam
File: sprite_vertex.glsl
Author: Brock Salmon
Created: 28AUG2025
*/

#version 460
#extension GL_GOOGLE_include_directive : require

#include "shared_layouts.glsl"

layout (location = 0) out vec4 outColour;
layout (location = 1) out vec2 outUV;
layout (location = 2) out uint outTextureID;

layout (push_constant) uniform constants {
  SpritePushConstants pc;
} PushConstants;

void main() {
  SpriteInfo sprite = PushConstants.pc.spriteBuffer.spriteInfos[gl_InstanceIndex];
  
  // Fill vertex position
  vec2 vertexPosition = SPRITE_BASE_VERTICES[gl_VertexIndex] * sprite.dimensions;
  gl_Position = (PushConstants.pc.viewProj * sprite.transform) * vec4(vertexPosition, 0, 1.0f);
  
  // Calc UV
  vec2 baseUV = SPRITE_BASE_UVS[gl_VertexIndex];
  outUV = baseUV * sprite.uv1 + (vec2(1,1) - baseUV) * sprite.uv0;
  
  outColour = sprite.colour;
  outTextureID = sprite.textureID;
}
