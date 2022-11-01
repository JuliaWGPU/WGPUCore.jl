## Load WGPU
using WGPUNative
using CEnum
using CEnum: Cenum

## default inits for non primitive types
weakRefs = WeakKeyDict() # |> lock

DEBUG = false

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

function logCallBack(logLevel::WGPULogLevel, msg::Ptr{Cchar})
    if logLevel == WGPULogLevel_Error
        level_str = "ERROR"
    elseif logLevel == WGPULogLevel_Warn
        level_str = "WARN"
    elseif logLevel == WGPULogLevel_Info
        level_str = "INFO"
    elseif logLevel == WGPULogLevel_Debug
        level_str = "DEBUG"
    elseif logLevel == WGPULogLevel_Trace
        level_str = "TRACE"
    else
        level_str = "UNKNOWN LOG LEVEL"
    end
    println("$(level_str) $(unsafe_string(msg))") # TODO MallocInfo
end

function SetLogLevel(loglevel::WGPULogLevel)
	# Commenting them for now TODO verify the link to MallocInfo
    # logcallback = @cfunction(logCallBack, Cvoid, (WGPULogLevel, Ptr{Cchar}))
    # wgpuSetLogCallback(logcallback)
    @info "Setting Log level : $loglevel"
    wgpuSetLogLevel(loglevel)
end

defaultInit(::Type{T}) where {T<:Number} = T(0)

defaultInit(::Type{T}) where {T} = begin
    if isprimitivetype(T)
        return T(0)
    else
        ins = []
        for t in fieldnames(T)
            push!(ins, defaultInit(fieldtype(T, t)))
        end
        t = T(ins...)
        r = WGPURef(t)
        f(x) = begin
            # global DEBUG
            # if DEBUG == true
                # @warn "Finalizing WGPURef $x"
            # end
            x = nothing
        end
        weakRefs[r] = (t, (ins .|> Ref)... )
        finalizer(f, r)
        return r
    end
end

defaultInit(::Type{WGPUNativeFeature}) = WGPUNativeFeature(0x10000000)

defaultInit(::Type{WGPUSType}) = WGPUSType(6)

defaultInit(::Type{T}) where {T<:Ptr{Nothing}} = Ptr{Nothing}()

defaultInit(::Type{Array{T,N}}) where {T} where {N} = zeros(T, DEFAULT_ARRAY_SIZE)

defaultInit(::Type{WGPUPowerPreference}) = WGPUPowerPreference_LowPower

defaultInit(::Type{Any}) = nothing

defaultInit(::Type{WGPUPredefinedColorSpace}) = WGPUPredefinedColorSpace_Srgb

defaultInit(::Type{Tuple{T}}) where {T} = Tuple{T}(zeros(T))

defaultInit(::Type{Ref{T}}) where {T} = Ref{T}()

defaultInit(::Type{NTuple{N,T}}) where {N,T} = zeros(T, (N,)) |> NTuple{N,T}

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
    r = WGPURef(t) # TODO MallocInfo
    f(x) = begin
        # @warn "Finalizing WGPURef $x"
        x = nothing
    end
    weakRefs[r] = (t, (ins .|> Ref)..., (others .|> Ref)...) # TODO MallocInfo
    finalizer(f, r)
    return r
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

function pointerRef(::Type{T}; kwargs...) where {T}
    pointer_from_objref(Ref(partialInit(T; kwargs...)))
end

function pointerRef(a::Ref{T}) where {T<:Any}
    return pointer_from_objref(a)
end

getBufferUsage(partials) = getEnum(WGPUBufferUsage, partials)

getBufferBindingType(partials) = getEnum(WGPUBufferBindingType, partials)

getShaderStage(partials) = getEnum(WGPUShaderStage, partials)

function listPartials(::Type{T}) where {T<:Cenum}
    pairs = CEnum.name_value_pairs(T)
    map((x) -> split(string(x[1]), "_")[end], pairs)
end
