/*
Project: 
File: bindless_descriptors.jai
Author: Brock Salmon
Created: 04AUG2025
*/

MAX_BINDLESS_RESOURCES : u32 : MAX_RESOURCE_POOL_ELEMENTS;
BINDLESS_TEXTURE_BINDING : u32 : 10;
MAX_UPDATES_PER_FRAME : u32 : 16;

create_bindless_descriptor_pool :: () -> VkDescriptorPool {
    poolSizes :: VkDescriptorPoolSize.[ .{ .COMBINED_IMAGE_SAMPLER, MAX_BINDLESS_RESOURCES } ];
    createInfo := VkDescriptorPoolCreateInfo.{ .DESCRIPTOR_POOL_CREATE_INFO, null,
					       .UPDATE_AFTER_BIND_BIT, MAX_BINDLESS_RESOURCES * poolSizes.count, cast(u32) poolSizes.count, poolSizes.data };

    pool : VkDescriptorPool;
    check_vk(vkCreateDescriptorPool(vk.device, *createInfo, null, *pool), "Failed to create Bindless Descriptor Pool");
    return pool;
}

create_bindless_descriptor_set :: () -> VkDescriptorSet {
    // Create the set layout
    binding := VkDescriptorSetLayoutBinding.{ BINDLESS_TEXTURE_BINDING, .COMBINED_IMAGE_SAMPLER, MAX_BINDLESS_RESOURCES, .ALL, null };

    bindlessFlags : VkDescriptorBindingFlags = .PARTIALLY_BOUND_BIT | .VARIABLE_DESCRIPTOR_COUNT_BIT | .UPDATE_AFTER_BIND_BIT;
    bindingFlagsCreateInfo := VkDescriptorSetLayoutBindingFlagsCreateInfo.{ .DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO, null, 1, *bindlessFlags };
    layoutCreateInfo := VkDescriptorSetLayoutCreateInfo.{ .DESCRIPTOR_SET_LAYOUT_CREATE_INFO, *bindingFlagsCreateInfo, .UPDATE_AFTER_BIND_POOL_BIT, 1, *binding };
    
    check_vk(vkCreateDescriptorSetLayout(vk.device, *layoutCreateInfo, null, *vk.bindlessDescriptorLayout), "Failed to create Bindless Descriptor Set Layout");
    
    // Allocate the descriptor set
    maxBinding : u32 = MAX_BINDLESS_RESOURCES - 1;
    descriptorCount := VkDescriptorSetVariableDescriptorCountAllocateInfo.{ .DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO, null, 1, *maxBinding };
    allocInfo := VkDescriptorSetAllocateInfo.{ .DESCRIPTOR_SET_ALLOCATE_INFO, *descriptorCount, vk.bindlessDescriptorPool, 1, *vk.bindlessDescriptorLayout };

    set : VkDescriptorSet;
    check_vk(vkAllocateDescriptorSets(vk.device, *allocInfo, *set), "Failed to create Bindless Descriptor Set");
    return set;
}

update_bindless_descriptor_textures :: () {
    if vk.bindlessTextureUpdates.count {
	bindlessDescriptorWrites    : [..] VkWriteDescriptorSet;
	bindlessDescriptorImageInfo : [..] VkDescriptorImageInfo;
	
	for vk.bindlessTextureUpdates {
	    if it_index == MAX_UPDATES_PER_FRAME - 1 then break;

	    imageInfo := array_add(*bindlessDescriptorImageInfo);
	    imageInfo.* = .{ vk.defaultSampler_Nearest, it.image.view, .SHADER_READ_ONLY_OPTIMAL };
	    
	    write := VkWriteDescriptorSet.{ .WRITE_DESCRIPTOR_SET, null, vk.bindlessDescriptorSet, BINDLESS_TEXTURE_BINDING, it.index, 1, .COMBINED_IMAGE_SAMPLER,
					    imageInfo, null, null };
	    array_add(*bindlessDescriptorWrites, write);
	}

	if vk.bindlessTextureUpdates.count < MAX_UPDATES_PER_FRAME {
	    array_reset(*vk.bindlessTextureUpdates);
	} else {
	    for 0 .. MAX_UPDATES_PER_FRAME-1 {
		array_ordered_remove_by_index(*vk.bindlessTextureUpdates, it);
	    }
	}

	if bindlessDescriptorWrites.count {
	    vkUpdateDescriptorSets(vk.device, cast(u32) bindlessDescriptorWrites.count, bindlessDescriptorWrites.data, 0, null);
	}

	array_reset(*bindlessDescriptorWrites);
	array_reset(*bindlessDescriptorImageInfo);
    }
}
