using WGPUCore
using WGPUCore: toCString
using WGPUNative

b = rand(UInt8, 23);
name = "shadercode";
wgslDescriptor = cStruct(
	WGPUShaderModuleWGSLDescriptor;
 	chain = cStruct(
	 		WGPUChainedStruct;
	 		next = C_NULL,
	 		sType = WGPUSType_ShaderModuleWGSLDescriptor
	) |> ptr |> unsafe_load, 
	 	code = pointer(b)
)

a = cStruct(
    WGPUShaderModuleDescriptor;
    nextInChain = wgslDescriptor |> ptr,
    label = toCString(name),
)

function loadWGSL(buffer::Vector{UInt8}; name = " UnknownShader ")
	chain = cStruct(
    		WGPUChainedStruct;
    		next = C_NULL,
    		sType = WGPUSType_ShaderModuleWGSLDescriptor
		)
    wgslDescriptor = cStruct(
    	WGPUShaderModuleWGSLDescriptor;
   		code = pointer(b),
   		chain = chain |> concrete
    )
    a = cStruct(
        WGPUShaderModuleDescriptor;
        nextInChain = wgslDescriptor |> ptr,
        label = toCString(name),
    )
    return (a, wgslDescriptor, chain)
end

c = loadWGSL(b)

