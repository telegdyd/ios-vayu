/*
 * MetalLayerHost.dylib: SpringBoard shows `metal_test layer`'s CAContext (metal_layer.m, docs/metal-roadmap.md task 10).
 *
 * FACT (2026-11-07, phone): a remote CAContext a root program makes -- displayable, display 1, level 1e6, ordered
 * above -- is made and committed to, but the window server draws nothing of it, not even a plain CALayer's colour
 * (hakios-gl's per-frame draw count unchanged). INFERENCE: on iOS 16 the window server puts on the panel the system
 * application's contexts and what they host, the way SpringBoard shows other processes' layers (a CALayerHost per
 * context; inject_sb.c's poster switcher is one). So this, loaded into SpringBoard by the tweak loader
 * (inject_tweaks.c: /var/jb/usr/lib/TweakInject, with MetalLayerHost.plist's Filter), hosts one context id:
 *
 *     notify "com.hakios.metal_layer.host"    read /private/var/tmp/metal_layer.host (a context id; 0 or no file: none)
 *                                             and host that context full screen above every window, or stop
 *
 * Nothing else: no hooks, no ElleKit. What it does goes to the console (oslogfwd), "MetalLayerHost:" lines.
 */
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <notify.h>
#include <stdio.h>
#include <unistd.h>

@interface CALayerHost : CALayer
@property uint32_t contextId;
@end

static CALayer *host;

static void
say(NSString *what)
{
	NSLog(@"MetalLayerHost: %@", what);
	fprintf(stderr, "MetalLayerHost: %s\n", [what UTF8String]);
}

static void
host_update(void)
{
	unsigned contextId = 0;
	FILE *file = fopen("/private/var/tmp/metal_layer.host", "r");

	if (file != NULL) {
		if (fscanf(file, "%u", &contextId) != 1) {
			contextId = 0;
		}
		fclose(file);
	}
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	[host removeFromSuperlayer];
	host = nil;
	if (contextId != 0) {
		UIWindow *top = nil;

		/* the window in front: the highest level among the shown ones */
		for (UIWindow *w in [[UIApplication sharedApplication] windows]) {
			if (![w isHidden] && (top == nil || [w windowLevel] >= [top windowLevel])) {
				top = w;
			}
		}
		Class hostClass = NSClassFromString(@"CALayerHost");
		if (top == nil || hostClass == Nil) {
			say([NSString stringWithFormat:@"no window (%@) or no CALayerHost class: context %u is not hosted", top, contextId]);
		} else {
			CALayerHost *h = [hostClass layer];

			h.contextId = contextId;
			h.frame = [[top layer] bounds];
			h.zPosition = 1e6;
			[[top layer] addSublayer:h];
			host = h;
			say([NSString stringWithFormat:@"context %u hosted full screen (%.0fx%.0f) in %@, level %.0f", contextId,
			    h.frame.size.width, h.frame.size.height, NSStringFromClass([top class]), (double)[top windowLevel]]);
		}
	} else {
		say(@"nothing hosted");
	}
	[CATransaction commit];
}

__attribute__((constructor)) static void
host_start(void)
{
	int token;

	notify_register_dispatch("com.hakios.metal_layer.host", &token, dispatch_get_main_queue(), ^(__unused int t) {
		host_update();
	});
	say(@"in SpringBoard; waiting for com.hakios.metal_layer.host");
}
