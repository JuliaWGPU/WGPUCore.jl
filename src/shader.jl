export loadWGSL

function load_wgsl(filename)
    b = read(filename)
    wgslDescriptor = cStruct(WGPUShaderModuleWGSLDescriptor)
    wgslDescriptor.chain = cStruct(
            WGPUChainedStruct;
            sType=WGPUSType_ShaderModuleWGSLDescriptor
        ) |> concrete 
    wgslDescriptor.code = pointer(b)
    
    a = cStruct(
        WGPUShaderModuleDescriptor;
        nextInChain = wgslDescriptor |> ptr,
        label = toCString(filename)
    )
    return (a, wgslDescriptor)
end

mutable struct GPUShaderModule <: Droppable
    label::Any
    internal::Any
    desc::Any
    device::Any
end

mutable struct WGSLSrcInfo
	shaderModuleDesc
	buffer
	chain
	wgslModuleDesc
	name
end

function loadWGSL(buffer::Vector{UInt8}; name = " UnnamedShader ")
   	chain = cStruct(
   		WGPUChainedStruct;
   		next = C_NULL,
   		sType = WGPUSType_ShaderModuleWGSLDescriptor
	) 
    wgslDescriptor = cStruct(
    	WGPUShaderModuleWGSLDescriptor;
		chain = chain |> concrete,
    	code = pointer(buffer)
    )
    a = cStruct(
        WGPUShaderModuleDescriptor;
        nextInChain = wgslDescriptor |> ptr ,
        label = toCString(name),
    )
    return WGSLSrcInfo(a, buffer, chain, wgslDescriptor, name)
end

function loadWGSL(buffer::IOBuffer; name = " UnknownShader ")
    b = read(buffer)
   	chain = cStruct(
   		WGPUChainedStruct;
   		next = C_NULL,
   		sType = WGPUSType_ShaderModuleWGSLDescriptor
	) 
    wgslDescriptor = cStruct(
    	WGPUShaderModuleWGSLDescriptor;
		chain = chain |> concrete,
    	code = pointer(b)
    )
    a = cStruct(
        WGPUShaderModuleDescriptor;
        nextInChain = wgslDescriptor |> ptr,
        label = toCString(name),
    )
    return WGSLSrcInfo(a, b, chain, wgslDescriptor, name)
end

function loadWGSL(fpath::String; name = " UnknownShader ")
    # TODO assert if filepath exists
    b = read(fpath)
   	chain = cStruct(
   		WGPUChainedStruct;
   		next = C_NULL,
   		sType = WGPUSType_ShaderModuleWGSLDescriptor
	) 
    wgslDescriptor = cStruct(
    	WGPUShaderModuleWGSLDescriptor;
		chain = chain |> concrete,
    	code = pointer(b)
    )
    a = cStruct(
        WGPUShaderModuleDescriptor;
        nextInChain = wgslDescriptor |> ptr,
        label = toCString(name),
    )
    return WGSLSrcInfo(a, b, chain, wgslDescriptor, name)
end

function loadWGSL(file::IOStream; name = " UnknownShader ")
    b = read(file)
   	chain = cStruct(
   		WGPUChainedStruct;
   		next = C_NULL,
   		sType = WGPUSType_ShaderModuleWGSLDescriptor
	) 
    wgslDescriptor = cStruct(
    	WGPUShaderModuleWGSLDescriptor;
		chain = chain |> concrete,
    	code = pointer(b)
    )
    a = cStruct(
        WGPUShaderModuleDescriptor;
        nextInChain = wgslDescriptor |> ptr,
        label = toCString(name == "UnknownShader" ? file.name : name),
    )
    return WGSLSrcInfo(a, b, chain, wgslDescriptor, name)
end

function createShaderModule(gpuDevice, label, shadercode, sourceMap, hints)
    shader = GC.@preserve shadercode wgpuDeviceCreateShaderModule(
        gpuDevice.internal[],
        shadercode |> ptr,
    )

    GPUShaderModule(label, shader |> Ref, shadercode, gpuDevice)
end
