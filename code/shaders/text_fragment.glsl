/*
Project: Loam
File: ui_text_fragment.glsl
Author: Brock Salmon
Created: 23JUN2025
*/

#version 460
#extension GL_GOOGLE_include_directive : require

#include "shared_layouts.glsl"

layout (location = 0) in vec4 inColour;
layout (location = 1) in vec2 inUV;
layout (location = 2) flat in uint inTextureIndex;

layout (location = 0) out vec4 fragColour;

void main() {   
  vec4 texColour = vec4(inColour.rgb, inColour.a * texture(bindlessTextures[nonuniformEXT(inTextureIndex)	], inUV).r);
  if (texColour.a < 0.05) { discard; }
  fragColour = texColour;
}

