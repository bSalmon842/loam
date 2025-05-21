/*
Project: Loam
File: mesh_vertex.glsl
Author: Brock Salmon
Created: 21MAY2025
*/

#version 460
#extension GL_EXT_buffer_reference : require

layout (location = 0) out vec3 outColour;

struct VertexInfo {
    vec3 position;
    vec3 normal;
    vec2 uv;
    vec4 colour;
};

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
}
