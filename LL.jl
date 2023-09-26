
struct ObjWrap
	ref::Any
end

struct Obj
	val::Int64
end

struct CStruct{T}
	ptr::Ptr{T}
	function CStruct(objType::DataType)
		cptr = Libc.malloc(sizeof(objType))
		new{objType}(cptr)
	end
end

function indirectionToField(cstruct::CStruct{T}, x::Symbol) where T
	fieldIdx::Int64 = Base.fieldindex(T, x)
	fieldOffset = Base.fieldoffset(T, fieldIdx)
	fieldType = Base.fieldtype(T, fieldIdx)
	fieldSize = fieldType |> sizeof
	offsetptr = getfield(cstruct, :ptr) + fieldOffset
	field = convert(Ptr{fieldType}, offsetptr)
end

function Base.getproperty(cstruct::CStruct{T}, x::Symbol) where T
	unsafe_load(indirectionToField(cstruct, x), 1)
end

function Base.getproperty(cstruct::CStruct{T}, x::Symbol) where T
	unsafe_load(indirectionToField(cstruct, x), 1)
end

function Base.setproperty!(cstruct::CStruct{T}, x::Symbol, v) where T
	field = indirectionToField(cstruct, x)
	unsafe_store!(field, v)
end

function Base.setproperty!(cstruct::CStruct{T}, p::Val{:ptr}, v) where T
	println("Hello")
end

function Base.getproperty(cstruct::CStruct{T}, p::Val{:ptr}) where T
	println("Hello")
end

function assign(cstruct::CStruct{T}, t::T) where T
	Libc.free(cstruct.ptr)
	
end	
