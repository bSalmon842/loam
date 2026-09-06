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
layout (location = 3) out vec3 outTangent;
layout (location = 4) out vec3 outBinormal;
layout (location = 5) out vec3 outLightDir;

layout (push_constant) uniform vertexConstants {
  VertexPushConstants pc;
} VertConstants;

void main() {
  VertexInfo loadedVertex = VertConstants.pc.vertexBuffer.vertices[gl_VertexIndex];
  vec4 vertPos = vec4(loadedVertex.position, 1.0f);
  vec4 worldPos = VertConstants.pc.transform * vertPos;
  gl_Position = world.viewProj * worldPos;
  
  outLightDir = normalize(world.lightPos.xyz - worldPos.xyz);
  
  outColour = loadedVertex.colour;
  outUV = loadedVertex.uv;
  
  mat3 normalMatrix = inverse(transpose(mat3(VertConstants.pc.transform)));
  vec3 n = loadedVertex.normal;
  n.z = -n.z;
  outNormal = normalize(normalMatrix * n);
  outTangent = normalize(normalMatrix * loadedVertex.tangent);
  outBinormal = normalize(normalMatrix * loadedVertex.binormal);
}
