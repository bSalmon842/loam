/*
Project: Loam
File: shared_layouts.glsl
Author: Brock Salmon
Created: 04JUN2025
*/

layout (set = 0, binding = 0) uniform sampler2D colourTexture;

struct VertexInfo {
    vec3 position;
    vec3 normal;
    vec2 uv;
    vec4 colour;
};
