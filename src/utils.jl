## Load WGPU
using WGPUNative
using CEnum
using CEnum: Cenum

export cStruct, CStruct, cStructPtr, ptr, concrete

## default inits for non primitive types
weakRefs = WeakKeyDict() # |> lock


DEBUG = true

function setDebugMode(mode)
    global DEBUG
    DEBUG = mode
end

defaultInit(::Type{T}) where {T<:Number} = T(0)

defaultInit(::Type{String}) = ""

defaultInit(::Type{T}) where {T} = begin
    if isprimitivetype(T)
        return T(0)
    # elseif isabstracttype(T)
    # 	return nothing
    else
        ins = []
        for t in fieldnames(T)
            push!(ins, defaultInit(fieldtype(T, t)))
        end
        t = T(ins...)
        return t
    end
end

defaultInit(::Type{WGPUNativeFeature}) = WGPUNativeFeature(0x10000000)

defaultInit(::Type{WGPUSType}) = WGPUSType(6)

defaultInit(::Type{T}) where {T<:Ptr{Nothing}} = Ptr{Nothing}()

defaultInit(::Type{Array{T,N}}) where {T} where {N} = zeros(T, DEFAULT_ARRAY_SIZE)

defaultInit(::Type{WGPUPowerPreference}) = WGPUPowerPreference_LowPower

# defaultInit(::Type{Any}) = nothing

defaultInit(::Type{Tuple{T}}) where {T} = Tuple{T}(zeros(T))

defaultInit(::Type{Ref{T}}) where {T} = Ref{T}()

defaultInit(::Type{NTuple{N,T}}) where {N,T} = zeros(T, (N,)) |> NTuple{N,T}


## Set Log callbacks
function getEnum(::Type{T}, query::String) where {T<:Cenum}
	get!(task_local_storage(), (T, query)) do
		begin
		    pairs = CEnum.name_value_pairs(T)
		    for (key, value) in pairs
		        pattern = split(string(key), "_")[end]
		        if pattern == query # TODO partial matching will be good but tie break will happen
		            return T(value)
		        end
		    end
		end
	end
end

function getEnum(::Type{T}, partials::Vector{String}) where {T<:Cenum}
	get!(task_local_storage(), tuple(partials...)) do
		begin
		    t = WGPUCore.defaultInit(T)
		    for partial in partials
		        e = getEnum(T, partial)
		        if e != nothing
		            t |= e
		        else
		            @error "$partial is not a member of $T"
		        end
		    end
		    return T(t)
		end
	end
end


function toCString(s::String)
	sNullTerminated = s*"\0"
	sPtr = pointer(sNullTerminated)
	dPtr = Libc.malloc(sizeof(sNullTerminated))
	dUInt8Ptr = convert(Ptr{UInt8}, dPtr)
	unsafe_copyto!(dUInt8Ptr, sPtr, sizeof(sNullTerminated))
end


## few more helper functions 
function unsafe_charArray(w::String)
    return pointer(Vector{UInt8}(w))
end

getBufferUsage(partials) = getEnum(WGPUBufferUsage, partials)

getBufferBindingType(partials) = getEnum(WGPUBufferBindingType, partials)

getShaderStage(partials) = getEnum(WGPUShaderStage, partials)

function listPartials(::Type{T}) where {T<:Cenum}
    pairs = CEnum.name_value_pairs(T)
    map((x) -> split(string(x[1]), "_")[end], pairs)
end

flatten(x) = reshape(x, (:,))
