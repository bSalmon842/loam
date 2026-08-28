/*
Project: Loam Engine
File: model.jai
Author: Brock Salmon
Created: 29JUL2026
*/

ModelNodeList :: Table(string, *ModelNode);

ModelNode :: struct {
    active : bool;
    
    parent   : *ModelNode;
    children : ModelNodeList;
    
    node : *SceneNode;
}

// In engine equivalent of a GLTF scene
Model :: struct {
    name : string;
    active : bool;
    
    using transform : Transform;

    resource : *GLTFResource;
    nodes : ModelNodeList;
}

make_model :: (modelName : string, transform : Transform, startActive : bool = false) -> *Model {
    model := New(Model);
    model.transform = transform;
    model.active = startActive;
    model.resource = get_resource(GLTFResource, modelName);
    if model.resource {
	gltf := model.resource.gltf;
	// TODO: We don't support multiple scenes here yet
	for gltf.scenes {
	    load_model_nodes(it.nodes, null, *model.nodes);
	}
    } else {
	log(.ERROR, "Failed to find gltf resource to initialise model with \"%\"", modelName);
    }
    
    return model;
}

load_model_nodes :: (gltfNodes : NodeList, parent : *ModelNode, modelNodes : *ModelNodeList) {
    for gltfNodes {
	node := New(ModelNode);
	node.active = true;
	node.parent = parent;
	node.node = it;
	load_model_nodes(it.children, node, *node.children);
	table_add(modelNodes, copy_string(it_index), node);
    }
}

update_model_animation :: (model : *Model) {
    
}

