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
layout (location = 3) out vec4 outTangent;
layout (location = 4) out vec3 outWorldPos;

layout (push_constant) uniform vertexConstants {
  VertexPushConstants pc;
} VertConstants;

void main() {
  VertexInfo loadedVertex = VertConstants.pc.vertexBuffer.vertices[gl_VertexIndex];
  vec4 vertPos = vec4(loadedVertex.position, 1.0f);
  vec4 worldPos = VertConstants.pc.transform * vertPos;
  outWorldPos = worldPos.xyz;
  gl_Position = world.viewProj * worldPos;
  
  outColour = loadedVertex.colour;
  outUV = loadedVertex.uv;

  mat3 modelMatrix = mat3(VertConstants.pc.transform);
  mat3 normalMatrix = inverse(transpose(modelMatrix));
  
  outNormal = normalize(normalMatrix * loadedVertex.normal);
  outTangent = vec4(normalize(modelMatrix * loadedVertex.tangent.xyz), loadedVertex.tangent.w);
}
