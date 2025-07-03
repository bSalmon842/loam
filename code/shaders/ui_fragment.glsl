/*
Project: Loam
File: ui_fragment.glsl
Author: Brock Salmon
Created: 23JUN2025
*/

#version 460
#extension GL_GOOGLE_include_directive : require

#include "shared_layouts.glsl"

layout (location = 0) in vec3 inColour;
layout (location = 1) in vec2 inUV;

layout (location = 0) out vec4 fragColour;

void main() {   
  vec4 texColour = vec4(inColour * texture(colourTexture, inUV).xyz, 1);
  if (texColour.a < 0.05) { discard; }
  fragColour = texColour;
}

