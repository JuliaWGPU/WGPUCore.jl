
using WGPU
using WGPU_jll
using WGPU: defaultInit, partialInit, pointerRef, unsafe_charArray


adapter = WGPU.requestAdapter(nothing, defaultInit(WGPUPowerPreference), WGPU.backend)

WGPU.backend

defaultDevice = WGPU.requestDevice(adapter)




