wgpuInstance = Ref{WGPUInstance}()

function getWGPUInstance()
    global wgpuInstance
    if wgpuInstance != C_NULL
        instanceDesc = cStruct(WGPUInstanceDescriptor)
        instanceDesc.nextInChain = C_NULL
        wgpuInstance[] = wgpuCreateInstance(instanceDesc  |> ptr)
    end
    return wgpuInstance
end
