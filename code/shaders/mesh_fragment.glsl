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
layout (location = 3) in vec3 inTangent;
layout (location = 4) in vec3 inBinormal;
layout (location = 5) in vec3 inLightDir;

layout (location = 0) out vec4 fragColour;

layout (push_constant) uniform fragmentConstants {
  layout(offset = 80)
  FragmentPushConstants pc;
} FragConstants;

void main() {
  MeshMaterial material = FragConstants.pc.material;
  
  vec4 baseColour = material.baseColour.factor * inColour;
  if (material.baseColour.index > -1) {
    baseColour *= sampleTexture(material.baseColour.index, NEAREST_SAMPLER, inUV);
  }
  
  vec3 normal = inNormal;
  if (material.normalTextureIndex > -1) {
      vec4 bumpMap = sampleTexture(material.normalTextureIndex, NEAREST_SAMPLER, inUV);
      bumpMap = (bumpMap * 2.0f) - 1.0f;
      vec3 bumpNormal = (bumpMap.x * inTangent) + (bumpMap.y * inBinormal) + (bumpMap.z * inNormal);
      normal = normalize(bumpNormal);
  }
  
  float lightValue = clamp(dot(normal, inLightDir) * world.lightPos.w, world.ambience, 1.0f);
  
  fragColour = clamp(vec4(baseColour.rgb * lightValue, baseColour.w), 0.0f, 1.0f);
}

