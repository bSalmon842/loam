/*
Project: Loam
File: grid_vertex.glsl
Author: Brock Salmon
Created: 14SEP2026
*/

#version 460
#extension GL_GOOGLE_include_directive : require

#include "shared_layouts.glsl"

layout (location = 0) out vec2 outUV;

const vec3 POSITIONS[4] = {
  { -0.5, 0.0,  0.5 },
  {  0.5, 0.0,  0.5 },
  { -0.5, 0.0, -0.5 },
  {  0.5, 0.0, -0.5 },
};

const float GRID_SIZE = 10.0f;

void main() {
  vec3 pos = POSITIONS[gl_VertexIndex];
  pos *= GRID_SIZE;

  gl_Position = world.viewProj * vec4(pos, 1.0);
  outUV = pos.xz;
}

