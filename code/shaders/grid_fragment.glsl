/*
Project: Loam
File: grid_fragment.glsl
Author: Brock Salmon
Created: 14SEP2026
*/

#version 460
#extension GL_GOOGLE_include_directive : require

#include "shared_layouts.glsl"

layout (location = 0) in vec2 inUV;
layout (location = 0) out vec4 fragColour;

struct GridFragmentPushConstants {
  float cellSize;
  float subcellSize;
  int padding[2];
  vec4 gridColour;
};

layout (push_constant) uniform fragmentConstants {
  GridFragmentPushConstants pc;
} FragConstants;

void main() {
  const float HALF_CELL_SIZE = FragConstants.pc.cellSize * 0.5f; 
  const float HALF_SUBCELL_SIZE = FragConstants.pc.subcellSize * 0.5f;
  
  const vec4 CELL_LINE_COLOUR = FragConstants.pc.gridColour;
  const vec4 SUBCELL_LINE_COLOUR = FragConstants.pc.gridColour * 0.5f;
    
  vec2 cellUV = mod(inUV + HALF_CELL_SIZE, FragConstants.pc.cellSize);
  vec2 subcellUV = mod(inUV + HALF_SUBCELL_SIZE, FragConstants.pc.subcellSize);

  vec2 distanceToCell = abs(cellUV - HALF_CELL_SIZE);
  vec2 distanceToSubCell = abs(subcellUV - HALF_SUBCELL_SIZE);

  vec2 lineCorrection = fwidth(inUV);
  vec2 cellLineThickness = 0.5f * ( 0.01f + lineCorrection );
  vec2 subcellLineThickness = 0.5f * ( 0.001f + lineCorrection );
  
  bvec2 inRangeOfCellLine = lessThan(distanceToCell, cellLineThickness);
  bvec2 inRangeOfSubcellLine = lessThan(distanceToSubCell, subcellLineThickness);
  
  vec4 colour = vec4(0.0);
  if (any(inRangeOfSubcellLine)) { colour = SUBCELL_LINE_COLOUR; }
  if (any(inRangeOfCellLine))    { colour = CELL_LINE_COLOUR; }

  if (colour.a < 0.05f) { discard; }
  
  fragColour = colour;
}
