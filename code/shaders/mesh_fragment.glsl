/*
Project: Loam
File: mesh_fragment.glsl
Author: Brock Salmon
Created: 21MAY2025
*/

#version 460

layout (location = 0) in vec3 inColour;

layout (location = 0) out vec4 fragColour;

void main() {   
  fragColour = vec4(inColour, 1);
}
