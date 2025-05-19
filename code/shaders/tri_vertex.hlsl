/*
Project: Loam
File: tri_vertex.hlsl
Author: Brock Salmon
Created: 19MAY2025
*/

struct VertexInput {
  uint vertexIndex : SV_VertexID;
};

struct VertexOutput {
  float4 position : SV_Position;
  float4 colour   : COLOR0;
};

VertexOutput main(VertexInput input) {
  VertexOutput output;

  float3 positions[3] = {
    float3( 0.75f,  0.75f, 0),
    float3(-0.75f,  0.75f, 0),
    float3( 0,     -0.75f, 0),
  };

  float4 colours[3] = {
    float4(1, 0, 0, 1),
    float4(0, 1, 0, 1),
    float4(0, 0, 1, 1),
  };

  output.position = float4(positions[input.vertexIndex], 1);
  output.colour = colours[input.vertexIndex];
  return output;
}
