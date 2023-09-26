
count = 0
mutable struct Arena{T, N}
	ptr::Ptr{T}
	function Arena(cArenaType::DataType, N::Int64)
		global count
		count += 1
		@info "Arena $count being prepared"
		cAPtr = Libc.malloc(sizeof(cArenaType)*N)
		f(x) = begin
			global count
			@info "Destroying Arena $count `$x`"
			count -= 1
			ptr = getfield(x, :ptr)
			Libc.free(ptr)
			setfield!(x, :ptr, typeof(ptr)(0))
		end
		obj = new{cArenaType, N}(cAPtr)
		finalizer(f, obj)
		return obj
	end
end

function Base.getindex(c::Arena{T, N}, idx::Int64) where {T, N}
	return unsafe_load(c.ptr, idx)
end

function Base.length(c::Arena{T, N}) where {T, N}
	return N
end

function Base.setindex!(c::Arena{T, N}, v::T, idx::Int64) where {T, N}
	unsafe_store!(c.ptr, v, idx)
end

Base.ndims(::Type{Arena{T, N}}) where {T, N} = 1
Base.size(arena::Arena{T, N}) where {T, N} = (N, )

Base.fill!(a::Arena{T, N}, v::T) where {T, N} = begin
	for idx in 1:N
		unsafe_store!(a.ptr, v, idx)
	end
end

a = Arena(Float32, 100)

a[1] = 2.0f0
a[2] = 1.0f0


a = nothing

GC.gc()

function getArenaInBytes(n)
	a = Arena(UInt8, n)
	return a
end

# Just wrap
function getArrayFromArenaWrap(n)
	a = getArenaInBytes(n)
	fill!(a, 10 |> UInt8)
	unsafe_wrap(Array, a.ptr, n)
end

# Just wrap
function getArrayFromArenaObj(n)
	a = getArenaInBytes(n)
	fill!(a, 10 |> UInt8)
	(unsafe_wrap(Array, a.ptr, n), a)
end



# Holding ref to original object in return
function getArrayFromArenaRef(n)
	a = getArenaInBytes(n)
	fill!(a, 10 |> UInt8)
	(unsafe_wrap(Array, a.ptr, n), Ref(a))
end

# holding ref; passing original obj with deref
function getArrayFromArenaDeref(n)
	a = getArenaInBytes(n) |> Ref
	fill!(a[], 10 |> UInt8)
	(unsafe_wrap(Array, a[].ptr, n), a)
end

function getArrayFromArenaPtrRef(n)
	ptr = getArenaInBytes(n).ptr
	unsafe_copyto!(ptr, repeat([10 |> UInt8,], n) |> pointer, n)
	(unsafe_wrap(Array, ptr, n), ptr |> Ref)
end

arr = getArrayFromArenaWrap(10)
arr
GC.gc()
arr

(arr1, ref1) = getArrayFromArenaObj(10)
arr1
GC.gc()
arr1

(arr2, ref2) = getArrayFromArenaRef(10)
arr2
GC.gc()
arr2

(arr3, ref3) = getArrayFromArenaDeref(10)
arr3
GC.gc()
arr3

(arr4, ref4) = getArrayFromArenaPtrRef(10)
arr4
GC.gc()
arr4

begin
	arr = getArrayFromArenaWrap(10)
	arr
	GC.gc()
	arr
end

begin
	(arr1, ref1) = getArrayFromArenaObj(10)
	arr1
	GC.gc()
	arr1
end

begin
	(arr2, ref2) = getArrayFromArenaRef(10)
	arr2
	GC.gc()
	arr2
end

begin
	(arr3, ref3) = getArrayFromArenaDeref(10)
	arr3
	GC.gc()
	arr3
end

begin
	(arr4, ref4) = getArrayFromArenaPtrRef(10)
	arr4
	GC.gc()
	arr4
end
