module Mod

mutable struct R
	a::Int32
	function R(a)
		r = new(a)
		f(r) = begin
			println("Finialize R : $r")
		end
		finalizer(f, r)
	end
end

mutable struct T
	a::Union{R, Nothing}
	function T(a::Int)
		r = R(a)
		t = new(r)
		f(t) = begin
			println("Finialize T : $t")
		end
		finalizer(f, t)
	end
end

function destroy(t::Ref{T}) where T
	@info getPointer(t.x)
	t[].a = nothing
	@info getPointer(t.x)
end

function destroy(t)
	@info getPointer(t)
	t = nothing
	@info getPointer(t)
end

function unsafe_pointer_from_objectref(@nospecialize(x))
    #= Warning Danger=#
    ccall(:jl_value_ptr, Ptr{Cvoid}, (Any,), x)
end

function getPointer(t::T) where T
	unsafe_pointer_from_objectref(t) |> (x) -> convert(Ptr{T}, x)
end

end


t = Mod.T(4214)

tptr = Mod.getPointer(t)
rptr = Mod.getPointer(t.a)

tload = unsafe_load(tptr)
rload = unsafe_load(rptr)

Mod.destroy(t)

tloadPtr = Mod.getPointer(tload)

Mod.destroy(t|>Ref)

tload = unsafe_load(tptr)

GC.gc(true)

tref = Ref(t)

Mod.destroy(tref)

t = 3

GC.gc()




