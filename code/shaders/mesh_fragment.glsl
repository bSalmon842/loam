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
layout (location = 1) in vec3 inNormal;
layout (location = 2) in vec2 inUV;

layout (location = 0) out vec4 fragColour;

layout (push_constant) uniform fragmentConstants {
  layout(offset = 96)
  FragmentPushConstants pc;
} FragConstants;

void main() {
  MeshMaterial material = FragConstants.pc.material;
  vec4 baseColour = material.baseColour.factor;
  if (material.baseColour.index > -1) {
      baseColour *= sampleTexture(material.normalTextureIndex, NEAREST_SAMPLER, inUV);
  }
  vec4 colour = inColour * baseColour;

  float lightValue = max(dot(inNormal, vec3(0,1,0)), 0.1f);
    
  fragColour = vec4(colour.xyz * lightValue, colour.w);
}

