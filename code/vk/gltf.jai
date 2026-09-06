/*
Project: Loam Engine
File: gltf.jai
Author: Brock Salmon
Created: 23JUL2026
*/

NodeList :: Table(string, *SceneNode);

SceneGraph :: struct {
    nodes : NodeList;
}

SceneNode :: struct {
    parent : *SceneNode;
    children : NodeList;

    worldTransform : Transform;
    localTransform : Transform;

    meshIndex : s64 = -1;
}

SceneMesh :: struct {
    name       : string;
    dimensions : Vector3;
    prims      : [] PrimitiveInfo;
}

SceneTexture :: struct {
    samplerIndex : s64 = -1;
    imageIndex : s64 = -1;
}

MaterialTexture :: struct {
    textureIndex      : s64 = -1;
    texCoordSet       : s64; // TEXCOORD_0, TEXCOORD_1, ... etc.
    normalScale       : float32 = 1.0;
    occlusionStrength : float32 = 1.0;
}

to_material_texture :: (textureInfo : GLTF_Texture_Info) -> MaterialTexture {
    matTex : MaterialTexture;
    matTex.textureIndex      = textureInfo.index;
    matTex.texCoordSet       = textureInfo.texcoord;
    matTex.normalScale       = textureInfo.scale;
    matTex.occlusionStrength = textureInfo.strength;
    return matTex;
}

SceneImage :: struct {
    name : string;
    image : *ImageResource;
}

PrimitiveInfo :: struct {
    active : bool = true;
    
    topology : VkPrimitiveTopology = .MAX_ENUM;
    materialIndex : s64 = -1;

    minBound : Vector3;
    maxBound : Vector3;
    using renderable : Renderable;
}

SceneSampler :: struct {
    sampler : *VkSampler;
    
    // NOTE: We don't really need to store these, but it helps for debugging outputs
    min     : VkFilter;
    mag     : VkFilter;
    mipMode : VkSamplerMipmapMode;
    wrapU   : VkSamplerAddressMode;
    wrapV   : VkSamplerAddressMode;
}

// An entire loaded scene in a GLTF file
GLTFModel :: struct {
    filename : string;
    metadata : string;

    defaultScene : s64;
    scenes    : Table(string, *SceneGraph);
    meshes    : [] *SceneMesh;
    materials : [] *Material;
    textures  : [] *SceneTexture;
    images    : [] *SceneImage;
    samplers  : [] *SceneSampler;
}

get_gltf_image_name :: (gltfName : string, gltfImage : GLTF_Image) -> string {
    return ifx gltfImage.uri.count > 0 then tprint("(%) %", gltfName, gltfImage.uri) else tprint("(%) Buffer View % (%)", gltfName, gltfImage.buffer_view, gltfImage.mime_type);
}

load_gltf_to_model :: (gltf : *GLTF_Data, name : string) -> *GLTFModel {
    model := New(GLTFModel);

    model.filename = copy_string(gltf.filepath);
    model.metadata = sprint("GLTF Version: % | Exported By: % | Copyright: %", gltf.asset.version, gltf.asset.generator, gltf.asset.copyright);

    model.samplers = NewArray(gltf.samplers.count, *SceneSampler);
    for gltfSampler : gltf.samplers {
	sampler := New(SceneSampler);
	model.samplers[it_index] = sampler;
	
	if #complete gltfSampler.min_filter == {
	    case .NEAREST; sampler.min = .NEAREST;
	    case .LINEAR;  sampler.min = .LINEAR;

	    case .NEAREST_MIPMAP_NEAREST; {
		sampler.min = .NEAREST;
		sampler.mipMode = .NEAREST;
	    }

	    case .LINEAR_MIPMAP_NEAREST; {
		sampler.min = .LINEAR;
		sampler.mipMode = .NEAREST;
	    }

	    case .NEAREST_MIPMAP_LINEAR; {
		sampler.min = .NEAREST;
		sampler.mipMode = .LINEAR;
	    }

	    case .LINEAR_MIPMAP_LINEAR; {
		sampler.min = .LINEAR;
		sampler.mipMode = .LINEAR;
	    }
	}
	
	sampler.mag = ifx gltfSampler.mag_filter == .NEAREST then .NEAREST else .LINEAR;

	if #complete gltfSampler.wrap_s == {
	    case .REPEAT;          sampler.wrapU = .REPEAT;
	    case .CLAMP_TO_EDGE;   sampler.wrapU = .CLAMP_TO_EDGE;
	    case .MIRRORED_REPEAT; sampler.wrapU = .MIRRORED_REPEAT;
	}

	if #complete gltfSampler.wrap_t == {
	    case .REPEAT;          sampler.wrapV = .REPEAT;
	    case .CLAMP_TO_EDGE;   sampler.wrapV = .CLAMP_TO_EDGE;
	    case .MIRRORED_REPEAT; sampler.wrapV = .MIRRORED_REPEAT;
	}

	sampler.sampler = New(VkSampler);
	create_vk_sampler(sampler.sampler, sampler.min, sampler.mag, sampler.mipMode, true, sampler.wrapU, sampler.wrapV);
    }
    
    model.images = NewArray(gltf.images.count, *SceneImage);
    for gltfImage : gltf.images {
	image := New(SceneImage);
	model.images[it_index] = image;
	image.name = copy_string(get_gltf_image_name(name, gltfImage));

	width, height, channels : s32;
	imageData := stbi_load_from_memory(gltfImage.data.data, cast(s32) gltfImage.data.count, *width, *height, *channels, 4);
	imageSize := VkExtent2D.{ cast(u32) width, cast(u32) height };
	vkImage := create_vk_image(imageData, cast(u64) (width * height * 4), .R8G8B8A8_UNORM, imageSize);
	// TODO: Check the image name is valid
	image.image = add_resource(image.name, vkImage, false);
    }
    
    model.textures = NewArray(gltf.textures.count, *SceneTexture);
    for gltfTexture : gltf.textures {
	texture := New(SceneTexture);
	model.textures[it_index] = texture;
	texture.samplerIndex = gltfTexture.sampler;
	texture.imageIndex = gltfTexture.source;
    }
    
    model.materials = NewArray(gltf.materials.count, *Material);
    for gltfMaterial : gltf.materials {
	material := New(Material);
	model.materials[it_index] = material;
	material.name = copy_string(gltfMaterial.name);
	material.baseColour.factor = make_vector4(gltfMaterial.metallic_roughness.base_color_factor);
	if gltfMaterial.metallic_roughness.has_base_color {
	    material.baseColour.texture = find_resource(ImageResource, get_gltf_image_name(name, gltf.images[gltfMaterial.metallic_roughness.base_color_texture.index]));
	}

	material.metalRough.factor = .{ gltfMaterial.metallic_roughness.metallic_factor, gltfMaterial.metallic_roughness.roughness_factor, 0, 0 };
	if gltfMaterial.metallic_roughness.has_metallic_roughness {
	    material.metalRough.texture = find_resource(ImageResource, get_gltf_image_name(name, gltf.images[gltfMaterial.metallic_roughness.metallic_roughness_texture.index]));
	}
	
	material.emissive.factor.xyz = make_vector3(gltfMaterial.emissive_factor);
	material.emissive.factor.w = gltfMaterial.emissive_strength;
	if gltfMaterial.has_emissive {
	    material.emissive.texture = find_resource(ImageResource, get_gltf_image_name(name, gltf.images[gltfMaterial.emissive_texture.index]));
	}
	
	if gltfMaterial.has_normal {
	    material.normalTexture = find_resource(ImageResource, get_gltf_image_name(name, gltf.images[gltfMaterial.normal_texture.index]));
	}
	
	material.isOpaque = gltfMaterial.alpha_mode == .OPAQUE;
	material.alphaCutoff = gltfMaterial.alpha_cutoff;
    }

    model.meshes = NewArray(gltf.meshes.count, *SceneMesh);
    for gltfMesh : gltf.meshes {
	mesh := New(SceneMesh);
	meshIndex := it_index;
	model.meshes[meshIndex] = mesh;
	mesh.name = copy_string(gltfMesh.name);
	
	mesh.prims = NewArray(gltfMesh.primitives.count, PrimitiveInfo);
	for gltfMesh.primitives {
	    prim := *mesh.prims[it_index];
	    if it.mode == {
		case .POINTS;         prim.topology = .POINT_LIST;
		case .LINES;          prim.topology = .LINE_LIST;
		case .LINE_LOOP;      log(.ERROR, "Invalid primitive mode in model \"%\", mesh \"%\"", model.filename, gltfMesh.name);
		case .LINE_STRIP;     prim.topology = .LINE_STRIP;
		case .TRIANGLES;      prim.topology = .TRIANGLE_LIST;
		case .TRIANGLE_STRIP; prim.topology = .TRIANGLE_STRIP;
		case .TRIANGLE_FAN;   prim.topology = .TRIANGLE_FAN;
	    }
	    
	    prim.materialIndex = it.material;
	    
	    indices : [..] u32;
	    if it.indices_accessor < 0 then log(.ERROR, "No Indices Accessor index for Prim % in GLTF Mesh \"%\" (%)", it_index, mesh.name, meshIndex);
	    read_buffer_from_accessor(gltf, gltf.accessors[it.indices_accessor], *indices);
	    
	    // Load Vertex Info
	    positions : [..] Vector3;
	    if it.position_accessor < 0 then log(.ERROR, "No Position Accessor index for Prim % in GLTF Mesh \"%\" (%)", it_index, mesh.name, meshIndex);
	    read_buffer_from_accessor_using_type(gltf, gltf.accessors[it.position_accessor], *positions);
	    
	    if positions.count == 0 {
		continue;
	    }

	    // Get Bounds
	    prim.minBound = .{ FLOAT32_MAX, FLOAT32_MAX, FLOAT32_MAX };
	    prim.maxBound = -prim.minBound;

	    for positions {
		if it.x < prim.minBound.x then prim.minBound.x = it.x;
		if it.x > prim.maxBound.x then prim.maxBound.x = it.x;

		if it.y < prim.minBound.y then prim.minBound.y = it.y;
		if it.y > prim.maxBound.y then prim.maxBound.y = it.y;

		if it.z < prim.minBound.z then prim.minBound.z = it.z;
		if it.z > prim.maxBound.z then prim.maxBound.z = it.z;
	    }
	    
	    normals : [..] Vector3;
	    if it.normal_accessor < 0 {
		log(.ERROR, "No Normal Accessor index for Prim % in GLTF Mesh \"%\" (%)", it_index, mesh.name, meshIndex);
	    } else {
		read_buffer_from_accessor_using_type(gltf, gltf.accessors[it.normal_accessor], *normals);
	    }

	    tangents : [..] Vector3;
	    // TODO: Implement mikktspace tangents if we have baked in tangents
	    /*
	    if it.tangent_accessor < 0 {
		log(.ERROR, "No Tangent Accessor index for Prim % in GLTF Mesh \"%\" (%)", it_index, mesh.name, meshIndex);
	    } else {
		read_buffer_from_accessor_using_type(gltf, gltf.accessors[it.tangent_accessor], *tangents);
	    }
	    */
	    
	    uvs : [..] Vector2;
	    if it.texcoord_0_accessor < 0 {
		log(.ERROR, "No TEXCOORD_0 Accessor index for Prim % in GLTF Mesh \"%\" (%)", it_index, mesh.name, meshIndex);
	    } else {
		read_buffer_from_accessor_using_type(gltf, gltf.accessors[it.texcoord_0_accessor], *uvs);
	    }
	    
	    colours : [..] Vector4;
	    if it.color_accessor < 0 {
		log(.ERROR, "No Colour Accessor index for Prim % in GLTF Mesh \"%\" (%)", it_index, mesh.name, meshIndex);
	    } else {
		read_buffer_from_accessor_using_type(gltf, gltf.accessors[it.color_accessor], *colours);
	    }
	    
	    vertices : [..] Vertex;
	    for positions {
		vertex : Vertex;
		vertex.position = it;
		vertex.position.z *= -1.0;
		vertex.normal   = ifx normals.count > 0  then normals[it_index]  else .{};
		//vertex.tangent  = ifx tangents.count > 0 then tangents[it_index] else .{};
		vertex.uv       = ifx uvs.count > 0      then uvs[it_index]      else .{};
		vertex.colour   = ifx colours.count > 0  then colours[it_index]  else make_vector4(1);
		array_add(*vertices, vertex);
	    }
	    
	    if tangents.count == 0 {
		// Generate our own tangents/binormals
		generate_mesh_tangents_binormals(name, indices, *vertices);
	    }
	    
	    if prim.materialIndex == -1 {
		prim.material = vk.errorMaterial;
	    } else {
		material := model.materials[prim.materialIndex];
		prim.material = material;
	    }
	    prim.buffers = New(GPUBuffers);
	    copy_mesh_to_gpu_buffers(indices, vertices, prim.buffers);
	}
    }
    
    model.defaultScene = gltf.scene;
    for gltfScene : gltf.scenes {
	sceneGraph := New(SceneGraph);
	table_add(*model.scenes, copy_string(gltfScene.name), sceneGraph);

	load_nodes(gltfScene.nodes, gltf.nodes, null, *sceneGraph.nodes);
    }
    
    return model;
}

load_nodes :: (nodeIndices : [] s64, gltfNodes : [..] GLTF_Node, parent : *SceneNode, nodes : *NodeList) {
    for nodeIndices {
	gltfNode := gltfNodes[it];
	
	node := New(SceneNode);
	node.meshIndex = gltfNode.mesh;
	node.parent = parent;
	{
	    position : Vector3    = ifx gltfNode.has_translation then make_vector3(gltfNode.translation) else .{};
	    rotation : Quaternion = ifx gltfNode.has_rotation    then make_quaternion(gltfNode.rotation) else .{};
	    scale    : Vector3    = ifx gltfNode.has_scale       then make_vector3(gltfNode.scale)       else make_vector3(1);
	    node.localTransform = make_transform(position, rotation, scale);
	    if node.parent {
		worldPosition := parent.worldTransform.position + position;
		worldRotation := parent.worldTransform.orientation + rotation;
		worldScale    := parent.worldTransform.scale * scale;
		node.worldTransform = make_transform(worldPosition, worldRotation, worldScale);
	    } else {
		node.worldTransform = node.localTransform;
	    }
	}
	
	load_nodes(gltfNode.children, gltfNodes, node, *node.children);
	table_add(nodes, copy_string(gltfNode.name), node);
    }
}

///////////////////////////
// DEBUG INFO /////////////
///////////////////////////

get_model_info_string :: (model : *GLTFModel) -> string {
    builder : String_Builder;

    print_to_builder(*builder, "\n==========\n");
    print_to_builder(*builder, "Model: %\n", model.filename);
    print_to_builder(*builder, "Metadata: \"%\"\n", model.metadata);
    print_to_builder(*builder, "\nDefault Scene Index: %\n", model.defaultScene);
    print_to_builder(*builder, "Scenes [%]:\n", model.scenes.count);
    sceneIndex : s64;
    for model.scenes {
	print_to_builder(*builder, "  [%] Scene \"%\":\n", sceneIndex, it_index);
	print_nodes_to_builder(*builder, "Nodes", model, it.nodes, 4);
	
	sceneIndex += 1;
    }
    
    print_to_builder(*builder, "\nMeshes [%]:\n", model.meshes.count);
    for model.meshes {
	print_to_builder(*builder, "  [%] Mesh \"%\":\n", it_index, it.name);

	print_to_builder(*builder, "    Prims: [%]:\n", it.prims.count);
	for it.prims {
	    print_to_builder(*builder, "      [%] Prim:\n", it_index);
	    print_to_builder(*builder, "        Topology Mode: %\n", it.topology);
	    if it.materialIndex != -1 then print_to_builder(*builder, "        Material: [%] \"%\"\n", it.materialIndex, model.materials[it.materialIndex].name);
	    if it.buffers then print_to_builder(*builder, "        GPU Buffer: %\n", it.buffers);
	}
    }
    
    print_to_builder(*builder, "\nMaterials [%]:\n", model.materials.count);
    for model.materials {
	print_to_builder(*builder, "  [%] Material \"%\":\n", it_index, it.name);
	print_to_builder(*builder, "    Base Colour Factor: %\n", it.baseColourFactor);
	if it.baseColourTexture then print_material_texture_to_builder(*builder, "Base Colour Texture", it.baseColourTexture, 4);
	
	print_to_builder(*builder, "    Metallic Roughness Factor: %\n", it.metalRoughnessFactor);
	if it.metalRoughnessTexture then print_material_texture_to_builder(*builder, "Metallic Roughness Texture", it.metalRoughnessTexture, 4);
	
	if it.normalTexture then print_material_texture_to_builder(*builder, "Normal Texture", it.normalTexture, 4);
	if it.occlusionTexture then print_material_texture_to_builder(*builder, "AO Texture", it.occlusionTexture, 4);
	
	print_to_builder(*builder, "    Emissive Factor: %\n", it.emissiveFactor);
	print_to_builder(*builder, "    Emissive Strength: %\n", it.emissiveStrength);
	if it.emissiveTexture then print_material_texture_to_builder(*builder, "Emissive Texture", it.emissiveTexture, 4);
	
	print_to_builder(*builder, "    Alpha Mode: %\n", it.alphaMode);
	print_to_builder(*builder, "    Alpha Cutoff: %\n", it.alphaCutoff);
    }

    print_to_builder(*builder, "\nTextures [%]:\n", model.textures.count);
    for model.textures {
	print_to_builder(*builder, "  [%] Texture:\n", it_index);
	print_to_builder(*builder, "    Sampler: [%]\n", it.samplerIndex);
	print_to_builder(*builder, "    Image: [%] \"%\"\n", it.imageIndex, model.images[it.imageIndex].name);
    }

    print_to_builder(*builder, "\nImages [%]:\n", model.images.count);
    for model.images {
	print_to_builder(*builder, "  [%] Image \"%\":\n", it_index, it.name);
	print_to_builder(*builder, "      Extent: %\n", it.image.extent);
	print_to_builder(*builder, "      Format: %\n", it.image.format);
    }

    print_to_builder(*builder, "\nSamplers [%]:\n", model.samplers.count);
    for model.samplers {
	print_to_builder(*builder, "  [%] Sampler:\n", it_index);
	print_to_builder(*builder, "    Min Filter:  %\n", it.min);
	print_to_builder(*builder, "    Mag Filter:  %\n", it.mag);
	print_to_builder(*builder, "    Mipmap Mode: %\n", it.mipMode);
	print_to_builder(*builder, "    Wrap Mode U: %\n", it.wrapU);
	print_to_builder(*builder, "    Wrap Mode V: %\n", it.wrapV);
    }
    
    print_to_builder(*builder, "==========\n\n");
    
    return builder_to_string(*builder);
}

print_nodes_to_builder :: (builder : *String_Builder, title : string, model : *GLTFModel, nodes : NodeList, indent : s64) {
    if nodes.count == 0 then return;

    indent_text :: (indentValue : s64) -> string {
	indentString : string;
	for 0 .. indentValue {
	    indentString = tprint("% ", indentString);
	}
	return indentString;
    }
    
    nodeIndex : s64;
    print_to_builder(builder, "%1%2 [%]:\n", indent_text(indent), title, nodes.count);
    for nodes {
	print_to_builder(builder, "%[%] Node \"%\":\n", indent_text(indent+2), nodeIndex, it_index);
	if it.meshIndex != -1 then print_to_builder(builder, "%Mesh: [%] \"%\"\n", indent_text(indent+4), it.meshIndex, model.meshes[it.meshIndex].name);

	print_nodes_to_builder(builder, "Children", model, it.children, indent+4);
	nodeIndex += 1;
    }
}

print_material_texture_to_builder :: (builder : *String_Builder, title : string, materialTexture : *MaterialTexture, indent : s64, isNormal := false, isOcclusion := false) {
    indent_text :: (indentValue : s64) -> string {
	indentString : string;
	for 0 .. indentValue {
	    indentString = tprint("% ", indentString);
	}
	return indentString;
    }
    
    nodeIndex : s64;
    print_to_builder(builder, "%1%2:\n", indent_text(indent), title);
    if materialTexture.textureIndex != -1 then print_to_builder(builder, "%Texture: [%]\n", indent_text(indent+2), materialTexture.textureIndex);
    print_to_builder(builder, "%Texture Coord Set: TEXCOORD_%\n", indent_text(indent+2), materialTexture.texCoordSet);
    if isNormal then print_to_builder(builder, "%Normal Scale: %\n", indent_text(indent+2), materialTexture.normalScale);
    if isOcclusion then print_to_builder(builder, "%Occlusion Strength: %\n", indent_text(indent+2), materialTexture.occlusionStrength);
}

