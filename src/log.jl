## Load WGPU
using WGPUNative
export SetLogLevel, logLevel

global logLevel::WGPULogLevel

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
	# Commenting them for now TODO verify the link to MallocInfo
    logcallback = @cfunction(logCallBack, Cvoid, (WGPULogLevel, Ptr{Cchar}))
    wgpuSetLogCallback(logcallback, C_NULL)
    @info "Setting Log level : $loglevel"
    global logLevel = loglevel
    wgpuSetLogLevel(loglevel)
end
