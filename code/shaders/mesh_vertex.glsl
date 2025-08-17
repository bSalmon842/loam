/*
Project: Loam
File: mesh_vertex.glsl
Author: Brock Salmon
Created: 21MAY2025
*/

#version 460
#extension GL_EXT_buffer_reference : require
#extension GL_GOOGLE_include_directive : require

#include "shared_layouts.glsl"

layout (location = 0) out vec4 outColour;
layout (location = 1) out vec2 outUV;

layout (push_constant) uniform constants {
  CommonPushConstants pc;
} PushConstants;

void main() {
    VertexInfo loadedVertex = PushConstants.pc.vertexBuffer.vertices[gl_VertexIndex];
    
    gl_Position = PushConstants.pc.renderMatrix * vec4(loadedVertex.position, 1.0f);
    outColour = loadedVertex.colour * PushConstants.pc.colour;
    outUV = loadedVertex.uv;
}
