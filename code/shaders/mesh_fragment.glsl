/*
Project: Loam
File: mesh_fragment.glsl
Author: Brock Salmon
Created: 21MAY2025
*/

#version 460
#extension GL_GOOGLE_include_directive : require

#include "shared_layouts.glsl"

layout (location = 0) in vec4 inColour;
layout (location = 1) in vec2 inUV;

layout (location = 0) out vec4 fragColour;

void main() {   
  fragColour = inColour * texture(colourTexture, inUV);
}

