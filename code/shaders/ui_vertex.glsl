/*
Project: Loam
File: ui_vertex.glsl
Author: Brock Salmon
Created: 23JUN2025
*/

#version 460
#extension GL_EXT_buffer_reference : require
#extension GL_GOOGLE_include_directive : require

#include "shared_layouts.glsl"

layout (location = 0) out vec3 outColour;
layout (location = 1) out vec2 outUV;

layout (buffer_reference, std430) readonly buffer VertexBuffer {
    VertexInfo vertices[];
};

layout (push_constant) uniform constants {
    mat4 renderMatrix;
    VertexBuffer vertexBuffer;
} PushConstants;

void main() {
  VertexInfo loadedVertex = PushConstants.vertexBuffer.vertices[gl_VertexIndex];
    
  gl_Position = PushConstants.renderMatrix * vec4(loadedVertex.position, 1.0f);
  outColour = loadedVertex.colour.xyz;
  outUV = loadedVertex.uv;
}


