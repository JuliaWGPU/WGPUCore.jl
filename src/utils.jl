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

function toCString(s::String)
	sNullTerminated = s*"\0"
	sPtr = pointer(sNullTerminated)
	dPtr = Libc.malloc(sizeof(sNullTerminated))
	dUInt8Ptr = convert(Ptr{UInt8}, dPtr)
	unsafe_copyto!(dUInt8Ptr, sPtr, sizeof(sNullTerminated))
end

mutable struct WGPURef{T}
    value::Union{T,Nothing}
end

function Base.getproperty(t::WGPURef{T}, s::Symbol) where {T}
    tmp = getfield(t, :value)
    return getproperty(tmp, s)
end

function Base.convert(::Type{T}, w::WGPURef{T}) where {T}
    return getfield(w, :value)
end

function Base.getindex(w::WGPURef{T}) where {T}
    return getfield(w, :value)
end

function Base.setindex!(w::WGPURef{T}, value) where {T}
    setfield!(w, :value, convert(T, value))
end

function Base.unsafe_convert(::Type{Ptr{T}}, w::Base.RefValue{WGPURef{T}}) where {T}
    return convert(Ptr{T}, Ref(getfield(w[], :value)) |> pointer_from_objref)
end

function partialInit(target::Type{T}; fields...) where {T}
    ins = []	# TODO MallocInfo
    others = [] # TODO MallocInfo
    inPairs = pairs(fields)
    for field in fieldnames(T)
        if field in keys(inPairs)
            push!(ins, inPairs[field]) # TODO MallocInfo 
        else
            push!(ins, defaultInit(fieldtype(T, field))) # TODO MallocInfo
        end
    end
    for field in keys(inPairs)
        if startswith(string(field), "xref") # TODO MallocInfo
            push!(others, inPairs[field])
        end
    end
    t = T(ins...)  # TODO MallocInfo
    return t
end

function addToRefs(a::T, args...) where {T}
    @assert islocked(weakRefs) == true "WeakRefs is supposed to be locked"
    if islocked(weakRefs)
        unlock(weakRefs)
        weakRefs[a] = args
        lock(weakRefs)
    end
    return a
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

# _wgpuInstance = Ptr{WGPUInstanceImpl}()

# function getWGPUInstance()
# 	global _wgpuInstance
# 	if _wgpuInstance == C_NULL
# 		_wgpuInstance = WGPUInstanceDescriptor(0) |> Ref |> wgpuCreateInstance
# 	end
# 	return _wgpuInstance
# end


# mutable struct CStruct{T}
# 	ptr::Ptr{T}
# 	function CStruct(cStructType::DataType)
# 		csPtr = Libc.malloc(sizeof(cStructType))
# 		f(x) = begin
#  			# @info "Destroying CStruct `$x`"
#  			ptr = getfield(x, :ptr)
#  			Libc.free(ptr)
#  			setfield!(x, :ptr, typeof(ptr)(0))
# 		end
# 		obj = new{cStructType}(csPtr)
# 		finalizer(f, obj)
# 		return obj
# 	end
# end

# function cStructFree(cstruct::CStruct{T}) where T
# 	ptr = getfield(cstruct, :ptr)
# 	Libc.free(ptr)
# end


# function indirectionToField(cstruct::CStruct{T}, x::Symbol) where T
# 	fieldIdx::Int64 = Base.fieldindex(T, x)
# 	fieldOffset = Base.fieldoffset(T, fieldIdx)
# 	fieldType = Base.fieldtype(T, fieldIdx)
# 	fieldSize = fieldType |> sizeof
# 	offsetptr = getfield(cstruct, :ptr) + fieldOffset
# 	field = convert(Ptr{fieldType}, offsetptr)
# end

# function Base.getproperty(cstruct::CStruct{T}, x::Symbol) where T
# 	unsafe_load(indirectionToField(cstruct, x), 1)
# end

# function Base.setproperty!(cstruct::CStruct{T}, x::Symbol, v) where T
# 	field = indirectionToField(cstruct, x)
# 	unsafe_store!(field, v)
# end


# ptr(cs::CStruct{T}) where T = getfield(cs, :ptr)

# # TODO this is not working right now
# # left it because its not priority.
# # Can always use getfield
# function Base.getproperty(cstruct::CStruct{T}, x::Val{:ptr}) where T
# 	getfield(cstruct, :ptr)
# end


# function cStruct(ctype::DataType; fields...)
# 	infields = []
# 	others = []
# 	cs = CStruct(ctype)
# 	inPairs = pairs(fields)
# 	for field in keys(inPairs)
# 		if field in fieldnames(ctype)
# 			setproperty!(cs, field, inPairs[field])
# 		elseif startswith(string(field), "xref")
# 			push!(others, inPairs[field])
# 		else 
# 			@warn """ CStruct : Setting property of non member field. \n
# 			Trying to set non member field `$field`.
# 			only supported fieldnames for `$ctype` are $(fieldnames(ctype))
# 			"""
# 		end
# 	end
#     # r = WeakRef(cs) # TODO MallocInfo
#     # f(x) = begin
#         # @warn "Finalizing CStruct `$ctype` $x"
#     # end
#     # weakRefs[r] = ((infields .|> Ref)..., (others .|> Ref)...) # TODO MallocInfo
#     # finalizer(f, r)
# 	return cs
# end

# function cStructPtr(ctype::DataType; fields...)
# 	return ptr(cStruct(ctype; fields...))
# end

# function concrete(cstruct::CStruct{T}) where T
# 	return cstruct |> ptr |> unsafe_load
# end

# TODO might cause few issues commenting for now
# This would help us while working with REPL
# function Base.fieldnames(cstruct::CStruct{T}) where T
	# Base.fieldnames(T)
# end

flatten(x) = reshape(x, (:,))