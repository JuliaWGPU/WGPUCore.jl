
mutable struct WGPUBackend <: WGPUAbstractBackend
    adapter::Ref{WGPUAdapter}
    device::Ref{WGPUDevice}
end


