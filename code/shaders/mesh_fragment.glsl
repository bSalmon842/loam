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
layout (location = 6) in vec3 inWorldPos;

layout (location = 0) out vec4 fragColour;

layout (push_constant) uniform fragmentConstants {
  layout(offset = 80)
  FragmentPushConstants pc;
} FragConstants;

const float MIN_PERCEPTUAL_ROUGHNESS = 0.1;
const float EPSILON = 1e-5;

float ggx_distribution(float nDotH, float alphaRoughness) {
  float alphaSq = sq(alphaRoughness);
  float denom = sq(nDotH) * (alphaSq - 1.0) + 1.0;
  return alphaSq / max(PI * sq(denom), EPSILON);
}

float smith_height_correlated(float nDotV, float nDotL, float alphaRoughness) {
  float alphaSq = sq(alphaRoughness);
  float viewMaskTerm = nDotL * sqrt(sq(nDotV) * (1.0 - alphaSq) + alphaSq);
  float lightShadowTerm = nDotV * sqrt(sq(nDotL) * (1.0 - alphaSq) + alphaSq);
  return 0.5 / max(viewMaskTerm + lightShadowTerm, EPSILON);
}

vec3 fresnel_reflectance(vec3 normalIncidenceReflectance, float vDotH) {
  float oneMinusCos = clamp(1.0 - vDotH, 0.0, 1.0);
  float oneMinusCosFifth = sq(sq(oneMinusCos)) * oneMinusCos;
  return normalIncidenceReflectance + (vec3(1.0) - normalIncidenceReflectance) * oneMinusCosFifth;
}

vec3 diffuse_lambert(vec3 diffuseAlbedo) {
  return diffuseAlbedo / PI;
}

vec3 compute_direct_light(vec3 normal, vec3 viewDir, vec3 lightDir, float alphaRoughness, vec3 normalIncidenceReflectance, vec3 diffuseAlbedo, vec3 incidentRadiance) {
  vec3 halfVector = normalize(viewDir + lightDir);
  float nDotV = clamp(dot(normal,  viewDir),    EPSILON, 1.0);
  float nDotL = clamp(dot(normal,  lightDir),   0,       1.0);
  float nDotH = clamp(dot(normal,  halfVector), 0,       1.0);
  float vDotH = clamp(dot(viewDir, halfVector), 0,       1.0);
  
  if (nDotL <= 0.0) {
    return vec3(0.0);
  }

  float normalDistribution = ggx_distribution(nDotH, alphaRoughness);
  float geoVisibility = smith_height_correlated(nDotV, nDotL, alphaRoughness);
  vec3 fresnelReflectance = fresnel_reflectance(normalIncidenceReflectance, vDotH);
  vec3 specContribution = normalDistribution * geoVisibility * fresnelReflectance;

  vec3 diffuseEnergyFrac = vec3(1.0) - fresnelReflectance;
  vec3 diffuseContribution = diffuseEnergyFrac * diffuse_lambert(diffuseAlbedo);

  return (diffuseContribution + specContribution) * incidentRadiance * nDotL;
}

vec3 compute_ambient_light(float perceptualRoughness, vec3 normalIncidenceReflectance, float nDotV, vec3 diffuseAlbedo, float ambientOcclusion) {
  vec3 ambientRadiance = world.ambience.rgb * world.ambience.a;

  float oneMinusRoughness = 1.0 - perceptualRoughness;
  vec3 roughnessAwareFresnel = normalIncidenceReflectance +
    (max(vec3(oneMinusRoughness), normalIncidenceReflectance) - normalIncidenceReflectance) *
    pow(clamp(1.0 - nDotV, 0.0, 1.0), 5.0);

  // TODO: Replace these with cubemaps
  vec3 ambientDiffuse = diffuseAlbedo * ambientRadiance;
  vec3 ambientSpec = roughnessAwareFresnel * ambientRadiance;

  return (ambientDiffuse + ambientSpec) * ambientOcclusion;
}

vec3 tone_mapping_ACES(vec3 linearHDR) {
  // Narkowicz cheap curve
  float a = 2.51;
  float b = 0.03;
  float c = 2.43;
  float d = 0.59;
  float e = 0.14;

  return clamp((linearHDR * (a * linearHDR + b)) / (linearHDR * (c * linearHDR + d) + e),
	       0.0, 1.0);
}

vec3 linear_to_SRGB(vec3 linear) {
  bvec3 useLinear = lessThanEqual(linear, vec3(0.0031308));
  vec3 linearSegment = linear * 12.92;
  vec3 gammaSegment = 1.055 * pow(linear, vec3(1.0 / 2.4)) - 0.055;

  return mix(gammaSegment, linearSegment, vec3(useLinear));
}

void main() {
  MeshMaterial material = FragConstants.pc.material;

  // Base Colour Calculation
  vec4 baseColour = material.baseColour.factor * inColour;
  if (material.baseColour.index != -1) {
    baseColour *= sampleTexture(material.baseColour.index, NEAREST_SAMPLER, inUV);
  }
  if (baseColour.a < material.alphaCutoff) { discard; }

  // PBR Shading
  vec4 orm;
  if (material.orm.index != -1) {
    orm = sampleTexture(material.orm.index, NEAREST_SAMPLER, inUV);
  } else {
    orm = material.orm.factor;
  }
  float rawO = orm.r;
  float rawR = orm.g;
  float rawM = orm.b;

  float ambientOcclusion = mix(1.0, rawO, material.orm.factor.r);
  float perceptualRoughness = clamp(rawR * material.orm.factor.g, MIN_PERCEPTUAL_ROUGHNESS, 1.0);
  float alphaRoughness = sq(perceptualRoughness);
  float metallic = clamp(rawM * material.orm.factor.b, 0.0, 1.0);

  // Metallic Setup (4% base reflection)
  vec3 diffuseAlbedo = baseColour.rgb * (1.0 - metallic);
  vec3 normalIncidenceReflectance = mix(vec3(0.04), baseColour.rgb, metallic);
  
  // Normals and View Vectors
  vec3 normal = inNormal;
  if (material.normalTextureIndex > -1) {
    vec3 orthoTangent = inTangent;
    orthoTangent = normalize(orthoTangent - inNormal * dot(inNormal, orthoTangent));

    vec3 orthoBi = inBinormal;
    orthoBi = normalize(orthoBi - inNormal * dot(inNormal, orthoBi) - orthoTangent * dot(orthoTangent, orthoBi));

    mat3 tangentToWorld = mat3(orthoTangent, orthoBi, inNormal);

    vec3 tangentSpaceNormal = sampleTexture(material.normalTextureIndex, NEAREST_SAMPLER, inUV).rgb * 2.0 - 1.0;
    tangentSpaceNormal = normalize(tangentSpaceNormal);

    normal = normalize(tangentToWorld * tangentSpaceNormal);
  }

  vec3 viewDir = normalize(world.cameraPos - inWorldPos);
  float nDotV = clamp(dot(normal, viewDir), EPSILON, 1.0);

  // Lighting
  // Single scene light
  vec3 radiance = vec3(0.0);
  {
    vec3 invLightDir = normalize(-inLightDir);
    vec3 incidentRadiance = world.lights[0].colour * world.lights[0].intensity;

    radiance += compute_direct_light(normal, viewDir, invLightDir, alphaRoughness, normalIncidenceReflectance, diffuseAlbedo, incidentRadiance);
  }
  // TODO: Implement multiple lights, currently just one directional light
  // Ambient Light
  radiance += compute_ambient_light(perceptualRoughness, normalIncidenceReflectance, nDotV, diffuseAlbedo, ambientOcclusion);

  // Exposure and Output
  vec3 displayColour = tone_mapping_ACES(radiance);
  //displayColour = linear_to_SRGB(displayColour);
  fragColour = vec4(displayColour, baseColour.a);
}

