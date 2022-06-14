
## Load WGPU
using WGPU_jll
using CEnum
using CEnum:Cenum
## default inits for non primitive types

## Set Log callbacks
function getEnum(::Type{T}, query::String) where T <: Cenum
	pairs = CEnum.name_value_pairs(T)
	for (key, value) in pairs
		pattern = split(string(key), "_")[end]
		if pattern == query # TODO partial matching will be good but tie break will happen
			return T(value)
		end
	end
end

function getEnum(::Type{T}, partials::Vector{String}) where T <: Cenum
	t = WGPU.defaultInit(T)
	for partial in partials
		e = getEnum(T, partial); 
		if e != nothing
			t |= e
		else
			@error "$partial is not a member of $T"
		end
	end
	return T(t)
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
        println("$(level_str) $(unsafe_string(msg))")
end

function SetLogLevel(loglevel::WGPULogLevel)
	logcallback = @cfunction(logCallBack, Cvoid, (WGPULogLevel, Ptr{Cchar}))
	wgpuSetLogCallback(logcallback)
	@info "Setting Log level : $loglevel"
	wgpuSetLogLevel(loglevel)
end

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

defaultInit(::Type{WGPUPowerPreference}) = WGPUPowerPreference_LowPower

defaultInit(::Type{Any}) = nothing

defaultInit(::Type{WGPUPredefinedColorSpace}) = WGPUPredefinedColorSpace_Srgb

defaultInit(::Type{Tuple{T}}) where T = Tuple{T}(zeros(T))

defaultInit(::Type{Ref{T}}) where T = Ref{T}()

WeakRefs = Dict()

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


function pointerRef(a::Ref{T}) where T<:Any
	return pointer_from_objref(a)
end
		
getBufferUsage(partials) = getEnum(WGPUBufferUsage, partials)

getBufferBindingType(partials) = getEnum(WGPUBufferBindingType, partials)

getShaderStage(partials) = getEnum(WGPUShaderStage, partials)

function listPartials(::Type{T}) where T <: Cenum
	pairs = CEnum.name_value_pairs(T)
	map((x) -> split(string(x[1]), "_")[end], pairs)
end

