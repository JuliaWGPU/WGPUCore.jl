all: cocoa.dylib

cocoa.dylib: cocoa.m
	clang -arch $(AARCH) -dynamiclib cocoa.m -I $(shell brew --prefix glfw)/include -o cocoa.dylib \
	-framework cocoa -L $(shell brew --prefix glfw)/lib -lGLFW -framework AppKit -framework Metal -framework QuartzCore

clean:
	rm cocoa.dylib
