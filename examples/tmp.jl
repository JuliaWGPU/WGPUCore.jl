using WGPU
using WGPU: partialInit, defaultInit

struct T
	a
	b
	c
end

struct S
	c
	d
end

struct D
	e
	f
end

function createEntry(::Type{T}; args...)
	t = partialInit(
		T;
		a = args[:a],
		b = args[:b],
		c = pointer(args[:c])
	)
	return t
end

function createEntry(::Type{S}; args...)
	ts = args[:c]
	ls = WGPU.WGPURef{T}[]
	for t in ts
		obj = createEntry(t.first; t.second...)
		push!(ls, obj)
	end
	lsls = map((x)->x[], ls)
	partialInit(
		S;
		c = lsls,
		d = 100.0f0,
		xref1 = ls
	)
end

function createEntry(::Type{D}; args...)
	e = createEntry(S; args...)
	d = partialInit(
		D;
		e = e,
		f = "Dtest"
	)
	return d
end

begin
	option = [
		:c => [
			T => [
				:a => 1,
				:b => 2,
				:c => "test1"
			],
			T => [
				:a => 3,
				:b => 4,
				:c => "test2"
			]
		],
		:d => 3.0f0
	]

	s = createEntry(D; option...)
end


a = 1

GC.gc()
