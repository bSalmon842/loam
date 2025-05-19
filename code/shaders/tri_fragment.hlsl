/*
Project: Loam
File: tri_fragment.hlsl
Author: Brock Salmon
Created: 19MAY2025
*/

// TODO: Move this to an include so there's less effort keeping this in line with the vertex shader
struct VertexOutput {
  float4 position : SV_Position;
  float4 colour   : COLOR0;
};

float4 main(VertexOutput input) : SV_Target {
  return input.colour;
}
