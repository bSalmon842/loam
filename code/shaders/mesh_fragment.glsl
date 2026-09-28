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
layout (location = 3) in vec4 inTangent;
layout (location = 4) in vec3 inWorldPos;

layout (location = 0) out vec4 fragColour;

layout (push_constant) uniform fragmentConstants {
  layout(offset = 80)
  FragmentPushConstants pc;
} FragConstants;

const float MIN_PERCEPTUAL_ROUGHNESS = 0.1;
const float EPSILON = 1e-5;

float ggx_distribution(float nDotH, float roughness) {
  float alphaRoughness = sq(roughness);
  float alphaSq = sq(alphaRoughness);
  float denom = sq(nDotH) * (alphaSq - 1.0) + 1.0;
  return alphaSq / max(PI * sq(denom), EPSILON);
}

float smith_geometry(float nDotV, float nDotL, float roughness) {
  float rough = roughness + 1.0;
  float lightRemap = sq(rough) / 8.0;
  float ggx1 = nDotV / (nDotV * (1.0 - lightRemap) + lightRemap);
  float ggx2 = nDotL / (nDotL * (1.0 - lightRemap) + lightRemap);
  
  return ggx1 * ggx2;
}

vec3 fresnel_reflectance(vec3 normalIncidenceReflectance, float hDotV) {
  return normalIncidenceReflectance + (1.0 - normalIncidenceReflectance) * pow(1.0 - hDotV, 5.0);
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
  vec4 orm = vec4(material.orm.factor.rgb, 1.0);
  if (material.orm.index != -1) {
    orm = sampleTexture(material.orm.index, NEAREST_SAMPLER, inUV);
  }
  
  float ambientOcclusion = orm.r;
  float roughness = orm.g;
  float metallic = orm.b;
  
  // Normals and View Vectors
  vec3 interpNormal = inNormal;
  vec3 normal = normalize(inNormal);
  if (material.normalTextureIndex > -1) {
    vec3 mapNormal = sampleTexture(material.normalTextureIndex, NEAREST_SAMPLER, inUV).rgb * 2.0 - 1.0;
    
    vec3 tangent = inTangent.xyz;
    vec3 bitangent = -inTangent.w * cross(normal, tangent);
    normal = normalize(mapNormal.x * tangent + mapNormal.y * bitangent + mapNormal.z * interpNormal);
  }

  vec3 viewDir = normalize(world.cameraPos - inWorldPos);
  vec3 reflectView = reflect(-viewDir, normal);

  // Metallic Setup (4% base reflection)
  vec3 normalIncidenceReflectance = mix(vec3(0.04), baseColour.rgb, metallic);

  // Lighting
  vec3 radiance = vec3(0.0);
  for (int lightIndex = 0; lightIndex < MAX_LIGHTS_IN_SCENE; ++lightIndex) {
    Light light = world.lights[lightIndex];
    if (light.intensity < EPSILON) { continue; }
    
    vec3 lightDir = normalize(light.position - inWorldPos);
    float lightDistance = length(light.position - inWorldPos);
    float attenuation = light.intensity / sq(lightDistance);
    vec3 incidentRadiance = light.colour * attenuation;

    vec3 halfVec = normalize(viewDir + lightDir);

    // BRDF
    float nDotL = max(dot(normal,  lightDir), 0.0);
    float nDotV = max(dot(normal,  viewDir),  0.0);
    float nDotH = max(dot(normal,  halfVec),  0.0);
    float hDotV = max(dot(halfVec, viewDir),  0.0);

    float distribution = ggx_distribution(nDotH, roughness);
    float geometry = smith_geometry(nDotV, nDotL, roughness);
    vec3 fresnel = fresnel_reflectance(normalIncidenceReflectance, hDotV);

    vec3 specNum = distribution * geometry * fresnel;
    float specDen = max(4.0 * nDotV * nDotL, EPSILON);
    vec3 specular = specNum / specDen;

    // Energy Conservation
    vec3 specCont = fresnel;
    vec3 diffCont = vec3(1.0) - specCont;
    diffCont *= 1.0 - metallic;

    radiance += (diffCont * baseColour.rgb / PI + specular) * incidentRadiance * nDotL;
  }

  vec3 ambient = vec3(0.03) * baseColour.rgb * ambientOcclusion;
  vec3 finalColour = ambient + radiance; // TODO: + Emissive
  finalColour = finalColour / (finalColour + vec3(1.0));
  // TODO: Gamma correction
  fragColour = vec4(finalColour, baseColour.a);
}

