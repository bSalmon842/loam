/*
Project: Loam
File: vk/descriptors.jai
Author: Brock Salmon
Created: 18MAY2025
*/

// --------------------------------------------------------------------- Descriptor Set Layout Builder
DescriptorSetBindings :: [..] VkDescriptorSetLayoutBinding;

add_binding :: (bindings : *DescriptorSetBindings, binding : u32, type : VkDescriptorType) {
    array_add(bindings, VkDescriptorSetLayoutBinding.{ binding, type, 1, 0, null });
}

create_descriptor_set_layout :: (bindings : *DescriptorSetBindings, device : VkDevice, shaderStages : VkShaderStageFlags) -> VkDescriptorSetLayout {
    for * bindings.* {
	it.stageFlags |= shaderStages;
    }

    createInfo := VkDescriptorSetLayoutCreateInfo.{ bindingCount = cast(u32) bindings.count, pBindings = bindings.data };
    setLayout : VkDescriptorSetLayout;
    check_vk(vkCreateDescriptorSetLayout(device, *createInfo, null, *setLayout), "Failed to create Descriptor Set Layout");

    // TODO: See if we can delete the bindings array or if we need to keep it
    
    return setLayout;
}

// --------------------------------------------------------------------- Descriptor Pool Allocator
PoolSizeRatio :: struct {
    type  : VkDescriptorType;
    ratio : float;
}

fill_pool_size_array :: (poolRatios : [] PoolSizeRatio, setCount : u32) -> [] VkDescriptorPoolSize {
    poolSizes : [..] VkDescriptorPoolSize;
    for poolRatios {
	array_add(*poolSizes, .{ it.type, cast(u32) (it.ratio * setCount) });
    }
    return poolSizes;
}

create_descriptor_pool :: (device : VkDevice, maxSets : u32, poolRatios : [] PoolSizeRatio) -> VkDescriptorPool {
    poolSizes := fill_pool_size_array(poolRatios, maxSets);
    createInfo := VkDescriptorPoolCreateInfo.{ maxSets = maxSets, poolSizeCount = cast(u32) poolSizes.count, pPoolSizes = poolSizes.data };

    pool : VkDescriptorPool;
    check_vk(vkCreateDescriptorPool(device, *createInfo, null, *pool), "Failed to create Descriptor Pool");
    return pool;
}

allocate_descriptor_set_from_pool :: (device : VkDevice, pool : VkDescriptorPool, layout : VkDescriptorSetLayout) -> VkDescriptorSet {
    allocInfo := VkDescriptorSetAllocateInfo.{ .DESCRIPTOR_SET_ALLOCATE_INFO, null, pool, 1, *layout };

    descriptorSet : VkDescriptorSet;
    check_vk(vkAllocateDescriptorSets(device, *allocInfo, *descriptorSet), "Failed to allocate Descriptor Set");
    return descriptorSet;
}

// --------------------------------------------------------------------- Dynamic Descriptor Pool Allocator
DynamicDescriptorPoolAllocator :: struct {
    ratios      : [..] PoolSizeRatio;
    full        : [..] VkDescriptorPool;
    ready       : [..] VkDescriptorPool;
    setsPerPool : u32;
}
MAX_SETS_PER_POOL :: 4092;

dynamic_descriptor_pool_allocator_init :: (allocator : *DynamicDescriptorPoolAllocator, device : VkDevice, initialSets : u32, poolRatios : [] PoolSizeRatio) {
    array_reset(*allocator.ratios);
    for poolRatios { array_add(*allocator.ratios, it); }

    pool := create_descriptor_pool(device, initialSets, poolRatios);
    allocator.setsPerPool = cast(u32) (initialSets * 1.5);
    array_add(*allocator.ready, pool);
}

dynamic_descriptor_pool_allocator_allocate :: (allocator : *DynamicDescriptorPoolAllocator, device : VkDevice, layout : VkDescriptorSetLayout) -> VkDescriptorSet {
    pool := dynamic_descriptor_pool_allocator_get_pool(allocator, device);
    allocInfo := VkDescriptorSetAllocateInfo.{ .DESCRIPTOR_SET_ALLOCATE_INFO, null, pool, 1, *layout };

    descriptorSet : VkDescriptorSet;
    createResult := vkAllocateDescriptorSets(device, *allocInfo, *descriptorSet);

    if createResult == .ERROR_OUT_OF_POOL_MEMORY || createResult == .ERROR_FRAGMENTED_POOL {
	array_add(*allocator.full, pool);
	pool = dynamic_descriptor_pool_allocator_get_pool(allocator, device);
	allocInfo.descriptorPool = pool;
	check_vk(vkAllocateDescriptorSets(device, *allocInfo, *descriptorSet), "Failed to allocate Descriptor Set (Dynamic)");
    }

    array_add(*allocator.ready, pool);
    return descriptorSet;
}

dynamic_descriptor_pool_allocator_reset_pools :: (allocator : *DynamicDescriptorPoolAllocator, device : VkDevice) {
    for allocator.ready { vkResetDescriptorPool(device, it, 0); }
    for allocator.full {
	vkResetDescriptorPool(device, it, 0);
	array_add(*allocator.ready, it);
    }
    array_reset(*allocator.full);
}

dynamic_descriptor_pool_allocator_destroy_pools :: (allocator : *DynamicDescriptorPoolAllocator, device : VkDevice) {
    for allocator.ready { vkDestroyDescriptorPool(device, it, null); }
    for allocator.full  { vkDestroyDescriptorPool(device, it, null); }

    array_reset(*allocator.ready);
    array_reset(*allocator.full);
}

dynamic_descriptor_pool_allocator_get_pool :: (allocator : *DynamicDescriptorPoolAllocator, device : VkDevice) -> VkDescriptorPool {
    if allocator.ready.count {
	return pop(*allocator.ready);
    } else {
	pool := create_descriptor_pool(device, allocator.setsPerPool, allocator.ratios);
	allocator.setsPerPool = cast(u32) min(allocator.setsPerPool * 1.5, MAX_SETS_PER_POOL);
	return pool;
    }
}

// --------------------------------------------------------------------- Descriptor Writing
DescriptorWriter :: struct {
    imageInfos  : [..] VkDescriptorImageInfo;
    bufferInfos : [..] VkDescriptorBufferInfo;
    writes      : [..] VkWriteDescriptorSet;
}

descriptor_write_image :: (writer : *DescriptorWriter, binding : u32, imageView : VkImageView, layout : VkImageLayout, sampler : VkSampler, type : VkDescriptorType) {
    info := array_add(*writer.imageInfos);
    info.* = VkDescriptorImageInfo.{ sampler, imageView, layout };

    write := VkWriteDescriptorSet.{ .WRITE_DESCRIPTOR_SET, null, null, binding, 0, 1, type, info, null, null };
    array_add(*writer.writes, write);
}

descriptor_write_buffer :: (writer : *DescriptorWriter, binding : u32, buffer : VkBuffer, offset : u32, size : u32, type : VkDescriptorType) {
    info := array_add(*writer.bufferInfos);
    info.* = VkDescriptorBufferInfo.{ buffer, offset, size };

    write := VkWriteDescriptorSet.{ .WRITE_DESCRIPTOR_SET, null, null, binding, 0, 1, type, null, info, null };
    array_add(*writer.writes, write);
}

clear_descriptor_writer :: (using writer : *DescriptorWriter) {
    array_reset(*imageInfos);
    array_reset(*bufferInfos);
    array_reset(*writes);
}

descriptor_writer_update_sets :: (writer : *DescriptorWriter, device : VkDevice, set : VkDescriptorSet) {
    for * writer.writes { it.dstSet = set; }
    vkUpdateDescriptorSets(device, cast(u32) writer.writes.count, writer.writes.data, 0, null);
}
