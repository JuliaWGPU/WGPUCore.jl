
## Load WGPU
using WGPU

## default inits for non primitive types

defaultInit(::Type{T}) where T<:Number = T(0)

defaultInit(::Type{T}) where T = begin
	if isprimitivetype(T)
	        return T(0)
	else
		ins = []
		for t = fieldnames(T)
			push!(ins, defaultInit(fieldtype(T, t)))
		end
	        return T(ins...)
        end
end


defaultInit(::Type{WGPUNativeFeature}) = WGPUNativeFeature(0x10000000)

defaultInit(::Type{WGPUSType}) = WGPUSType(6)

defaultInit(::Type{T}) where T<:Ptr{Nothing} = Ptr{Nothing}()

defaultInit(::Type{Array{T, N}}) where T where N = zeros(T, DEFAULT_ARRAY_SIZE)

defaultInit(::Type{WGPUPowerPreference}) = WGPUPowerPreference(1)


function partialInit(target::Type{T}; fields...) where T
	ins = []
	inPairs = pairs(fields)
	for field in fieldnames(T)
        	if field in keys(inPairs)
	                push!(ins, inPairs[field])
			else
			        push!(ins, defaultInit(fieldtype(T, field)))
			end
		end
	return T(ins...)
end

## few more helper functions

function unsafe_charArray(w::String)
    return pointer(Vector{UInt8}(w))
end

function pointerRef(::Type{T}; kwargs...) where T
    pointer_from_objref(Ref(partialInit(
        T;
        kwargs...)))
end


