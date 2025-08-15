/*
Project: Loam
File: ui_vertex.glsl
Author: Brock Salmon
Created: 23JUN2025
*/

#version 460
#extension GL_GOOGLE_include_directive : require

#include "shared_layouts.glsl"

layout (location = 0) out vec4 outColour;
layout (location = 1) out vec2 outUV;
layout (location = 2) out uint outTextureIndex;

layout (push_constant) uniform constants {
  CommonPushConstants pc;
} PushConstants;

void main() {
  VertexInfo loadedVertex = PushConstants.pc.vertexBuffer.vertices[gl_VertexIndex];
    
  gl_Position = PushConstants.pc.renderMatrix * vec4(loadedVertex.position, 1.0f);
  outColour = loadedVertex.colour * PushConstants.pc.colour;
  outUV = loadedVertex.uv;
  outTextureIndex = PushConstants.pc.textureIndex;
}


