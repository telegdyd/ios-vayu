/*
 * metal_ca_try.dylib (vayu, docs/metal-roadmap.md task 11): the window server on a Metal plug-in that is not the image's,
 * with no reflash.
 *
 * Metal opens its plug-in with +[NSBundle bundleWithPath:@"/System/Library/Extensions/<MetalPluginName>.bundle"]
 * (docs/ru/metal.md, getMetalPluginClassForService), and that directory is the read-only root with the image's bundle
 * bound on it by init (bindfs, which nobody but process 1 may mount). So this library, inserted into backboardd by the
 * kernel (sysctl kern.exec_inject, set by tools/metal-ca-run.sh), gives that one path the bundle uploaded to
 * /private/var/tmp/task11 instead, while it is there. The bundle's own rule still decides who is shown the device
 * (HakiosMetal.clients, in /private/var/tmp too). /private/var/tmp is emptied at boot and the sysctl is set again from
 * the image at boot, so one reboot is the window server on the image's plug-in (GL) again.
 *
 * The method, not IOKit's MetalPluginName read: dyld's interposing does not reach calls between the shared cache's own
 * libraries here (FACT, try2: an interposed IORegistryEntryCreateCFProperty saw libhakios's call, never Metal's).
 *
 * SPDX-License-Identifier: MIT
 */
#include <CoreFoundation/CoreFoundation.h>
#include <fcntl.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define SYSTEM_BUNDLE   "/System/Library/Extensions/HakiosMetal.bundle"
#define TRY_BUNDLE      "/private/var/tmp/task11/HakiosMetal.bundle"

static void
say(const char *line)
{
	int fd = open("/dev/console", O_WRONLY | O_NOCTTY);

	if (fd >= 0) {
		char buf[300];

		snprintf(buf, sizeof(buf), "metal_ca_try[%d]: %s\n", getpid(), line);
		(void)!write(fd, buf, strlen(buf));
		close(fd);
	}
}

static id (*bundle_with_path)(id, SEL, id);

static id
try_bundle_with_path(id self, SEL _cmd, id path)
{
	struct stat st;
	char p[1024] = "";

	if (path != nil && CFStringGetCString((CFStringRef)path, p, sizeof(p), kCFStringEncodingUTF8) &&
	    strcmp(p, SYSTEM_BUNDLE) == 0 && stat(TRY_BUNDLE "/HakiosMetal", &st) == 0) {
		say("+[NSBundle bundleWithPath:" SYSTEM_BUNDLE "] answered with " TRY_BUNDLE);
		path = (id)CFSTR(TRY_BUNDLE);
	}
	return bundle_with_path(self, _cmd, path);
}

__attribute__((constructor)) static void
loaded(void)
{
	Class bundle = objc_getClass("NSBundle");
	Method m = bundle != Nil ? class_getClassMethod(bundle, sel_registerName("bundleWithPath:")) : NULL;

	if (m == NULL) {
		say("no +[NSBundle bundleWithPath:]: the image's plug-in stays");
		return;
	}
	bundle_with_path = (id (*)(id, SEL, id))method_setImplementation(m, (IMP)try_bundle_with_path);
	say("in this process; Metal's plug-in is " TRY_BUNDLE " while it is there");
}
