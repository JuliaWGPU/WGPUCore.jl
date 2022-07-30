module CacheMod

cache = WeakKeyDict()

function addToCache(k, v)
	r = WeakRef(k)
	cache[r] = v
	return r
end


end

mutable struct T
	a
	function T(a)
		t = new(a)
		finalizer(
			(t) -> begin
				@warn "Finalizing $t"
			end,
			t
		)
	end
end

# t = Ref(T(10))
# 
# tref = CacheMod.addToCache(t, 10)

# t = T(10)
function evall()
	t = T(10)
	tref = Ref(t)
	
	CacheMod.addToCache(tref, 10)
	return tref
end


t = evall()

# t = 10


