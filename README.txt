Grand Unified Source Tree for Oolite
====================================

Oolite for all platforms can be built from this repository.
Here is a quick guide to the source tree.

1. Guidelines
-------------
Nothing except makefiles/xcode projects, directories, and this readme
file should appear in the top level directory.
The deps directory should contain dependencies that are useful to carry
along to build binary packages. The dependencies directory should
be named:
   Opsys-cpuarch-deps
Opsys should be exactly as reported by 'uname' with no flags (case
sensitive!). The cpuarch should be the cpu architecture reported by
'uname -p' (except i686, i586 etc should be translated to x86).
This allows build scripts to automatically package up the right
dependency tree in tarball installers.

2. Contents
-----------
autopackage       Directory for the apspec file for the Linux autopackage
Asset Source      Files used to create the various PNG and sound files
deps              Dependencies for all plaforms:
   Cocoa-deps     Dependencies for Mac OS X (macppc and macintel platforms)
   Linux-x86-deps Dependencies for Linux on x86 processors
   scripts        Scripts and script fragments for tarball/autopackage
Doc               Documentation (including user guides)
FreeDesktop       Files for GNOME/KDE desktop launchers
Oolite-importer   (OS X) The oolite importer
Oolite.xcodeproj  The OS X Xcode project to build Oolite
OSX-SDL           Project files for the SDL version of Oolite on OS X
                  (*very* seldom used, more of a curiosity)
Resources         Files that live in the application bundle's 
                  Contents/Resources directory (AI, config, textures etc).
src               Objective-C and C sources, incuding header files:
   Core           Files that are compiled on all platforms
   SDL            Files that are only compiled for platforms that use SDL
   Cocoa          Files that are only compiled on Mac OS X without SDL
tools             Various tools for preparing files, builds, releases etc.

3. Building
-----------
On Mac OS X, you will need the latest version of Xcode and OS X 10.4 (Tiger).
You will also need all the relevant frameworks (they come with Xcode).
If you don't yet have Xcode you can get it from the Apple Developer
Connection (see the Apple web site) - ADC membership to get Xcode is
free, and it's a rather nice IDE.
Then double click on the Xcode project in the Finder, and hit Build.

On Linux, BSD and other Unix platforms, you will need to get GNUstep and
SDL development libraries in addition to what is usually installed by
default if you choose to install the development headers/libraries etc.
when initially installing the OS. For most Linux distros, GNUstep and SDL 
development libraries come prepackaged - just apt-get/yum install the
relevant files. On others you may need to build them from source.
In particular, you need the SDL_image and SDL_Mixer libraries; these
don't always come with the base SDL development kit.
Then just type 'make'.

If you want to make the Linux autopackage, after getting the Autopackage
development kit, just type 'makeinstaller', and a package file will be
deposited in the top level.

[Nic, please put some build instructions for Windows here!]

4. Running
----------
On OS X, you can run from Xcode by clicking on the appropriate icon
(or choosing 'Build and Run').
On Linux/BSD/Unix, in a terminal, type 'openapp oolite'

