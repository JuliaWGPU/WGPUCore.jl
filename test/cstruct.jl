using WGPUCore
using WGPUCore: toWGPUString
using WGPUNative

b = rand(UInt8, 23);
name = "shadercode";



function getDesc()
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
	    label = toWGPUString(name),
	)
	
end

