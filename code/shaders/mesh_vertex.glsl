/*
Project: Loam
File: mesh_vertex.glsl
Author: Brock Salmon
Created: 21MAY2025
*/

#version 460
#extension GL_GOOGLE_include_directive : require

#include "shared_layouts.glsl"

layout (location = 0) out vec4 outColour;
layout (location = 1) out vec3 outNormal;
layout (location = 2) out vec2 outUV;

layout (push_constant) uniform vertexConstants {
  VertexPushConstants pc;
} VertConstants;

void main() {
  VertexInfo loadedVertex = VertConstants.pc.vertexBuffer.vertices[gl_VertexIndex];
  
  gl_Position = VertConstants.pc.renderMatrix * vec4(loadedVertex.position, 1.0f);
  
  outColour = loadedVertex.colour * VertConstants.pc.colour;
  outNormal = loadedVertex.normal;
  outUV = loadedVertex.uv;
}
