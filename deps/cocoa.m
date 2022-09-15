#include "Cocoa/Cocoa.h"
#define GLFW_INCLUDE_NONE
#define GLFW_EXPOSE_NATIVE_COCOA

#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

CAMetalLayer * getMetalLayer() {
    CAMetalLayer *swapchain = [CAMetalLayer layer];
  	return swapchain;
}

void wantLayer(void * ptr) {
	NSWindow *nswindow = ptr;
	[nswindow.contentView setWantsLayer:YES];
}

void setMetalLayer(void * ptr, void * layer) {
	NSWindow *nswindow = ptr;
	[nswindow.contentView setLayer:layer];
}
