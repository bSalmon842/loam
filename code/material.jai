/*
Project: Loam Engine
File: material.jai
Author: Brock Salmon
Created: 28AUG2026
*/

TextureWithFactor :: struct {
    texture : *ImageResource;
    factor  := Vector4.{1,1,1,1};
}

Material :: struct {
    name : string;
    
    baseColour    : TextureWithFactor;
    metalRough    : TextureWithFactor;
    emissive      : TextureWithFactor; // Factor is xyz, strength is w
    normalTexture : *ImageResource;

    isOpaque    : bool;
    alphaCutoff : float32;
}

GPUTextureWithFactor :: struct {
    factor       := Vector4.{1,1,1,1};
    textureIndex : s32 = -1;
    padding0 : s32;
    padding1 : s32;
    padding2 : s32;
} #no_padding;

GPUMaterial :: struct {
    baseColour : GPUTextureWithFactor;
    metalRough : GPUTextureWithFactor;
    emissive   : GPUTextureWithFactor; // xyz is factor, w is strength
    normalIndex : s32 = -1;
    isOpaque    : bool;
    alphaCutoff : float32;
} #no_padding;

to_gpu_tex_with_factor :: (texFactor : TextureWithFactor) -> GPUTextureWithFactor {
    return .{ texFactor.factor, ifx texFactor.texture then cast(s32) texFactor.texture.index else cast(s32)-1, 0, 0, 0 };
}

to_gpu_material :: (material : *Material) -> GPUMaterial {
    return .{
	to_gpu_tex_with_factor(material.baseColour),
	to_gpu_tex_with_factor(material.metalRough),
	to_gpu_tex_with_factor(material.emissive),
	ifx material.normalTexture then cast(s32)material.normalTexture.index else cast(s32)-1,
	material.isOpaque, material.alphaCutoff
    };
}

generate_mesh_tangents_binormals :: (name : string, indices : [] u32,vertices : *[] Vertex) {
    if indices.count % 3 != 0 {
	log(.ERROR, "Index count (%) for mesh \"%\" is not divisible by 3, cannot generate tangents and binormals", indices.count, name);
    }

    build_calc_vertex :: () -> TangentCalcVertex #expand {
	base := `vertices.*[`indices[`indexIndex]];
	`indexIndex += 1;
	return TangentCalcVertex.{ base.position, base.normal, base.uv };
    }
    
    faceCount := indices.count / 3;
    indexIndex := 0;
    for 1 .. faceCount {
	vert1 := build_calc_vertex();
	vert2 := build_calc_vertex();
	vert3 := build_calc_vertex();
	
	tangent, binormal := calculate_tangents_binormals_for_tri(vert1, vert2, vert3);

	vertices.*[indices[indexIndex-1]].tangent = tangent;
	vertices.*[indices[indexIndex-1]].binormal = binormal;

	vertices.*[indices[indexIndex-2]].tangent = tangent;
	vertices.*[indices[indexIndex-2]].binormal = binormal;

	vertices.*[indices[indexIndex-3]].tangent = tangent;
	vertices.*[indices[indexIndex-3]].binormal = binormal;
    }
}

calculate_tangents_binormals_for_tri :: (vert1 : TangentCalcVertex, vert2 : TangentCalcVertex, vert3 : TangentCalcVertex) -> Vector3, Vector3 {
    tangent, binormal : Vector3;
    
    faceVec1 := vert2.position - vert1.position;
    faceVec2 := vert3.position - vert1.position;

    faceU := Vector2.{ vert2.uv.x - vert1.uv.x, vert3.uv.x - vert1.uv.x };
    faceV := Vector2.{ vert2.uv.y - vert1.uv.y, vert3.uv.y - vert1.uv.y };

    denom := 1.0 / determinant(faceU, faceV);

    tangent.x = (faceV.y*faceVec1.x - faceV.x*faceVec2.x) * denom;
    tangent.y = (faceV.y*faceVec1.y - faceV.x*faceVec2.y) * denom;
    tangent.z = (faceV.y*faceVec1.z - faceV.x*faceVec2.z) * denom;

    binormal.x = (faceU.x*faceVec2.x - faceU.y*faceVec1.x) * denom;
    binormal.y = (faceU.x*faceVec2.y - faceU.y*faceVec1.y) * denom;
    binormal.z = (faceU.x*faceVec2.z - faceU.y*faceVec1.z) * denom;
    
    tanLength := length(tangent);
    tangent /= tanLength;
    
    binLength := length(binormal);
    binormal /= binLength;
    
    return tangent, binormal;
}


