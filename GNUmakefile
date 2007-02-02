include $(GNUSTEP_MAKEFILES)/common.make
CP = cp
vpath %.m src/SDL src/Core src/Core/JavaScript
vpath %.h src/SDL src/Core src/Core/JavaScript
vpath %.c src/SDL src/Core src/BSDCompat
GNUSTEP_INSTALLATION_DIR = $(GNUSTEP_USER_ROOT)
ifeq ($(GNUSTEP_HOST_OS),mingw32)
	ADDITIONAL_INCLUDE_DIRS = -Ideps/Windows-x86-deps/include
	ADDITIONAL_OBJC_LIBS = -lglu32 -lopengl32 -lmingw32 -lSDLmain -lSDL -lSDL_mixer -lSDL_image -lgnustep-base -ljs32
	ADDITIONAL_CFLAGS = -DNO_SHADERS -DLINUX -DWIN32 -DNEED_STRLCPY `sdl-config --cflags`
# note the vpath stuff above does not add the %.h directories to the gcc command, so adding them explicitly
	ADDITIONAL_OBJCFLAGS = -DNO_SHADERS -DLOADSAVEGUI -DLINUX -DWIN32 -DXP_WIN -DHAVE_SOUND -Wno-import `sdl-config --cflags` -Isrc/SDL -Isrc/Core -Isrc/Core/JavaScript
	oolite_LIB_DIRS += -L$(GNUSTEP_LOCAL_ROOT)/lib -Ldeps/Windows-x86-deps/lib
else
	ADDITIONAL_INCLUDE_DIRS = -Isrc/SDL -Isrc/Core -Isrc/BSDCompat
	ADDITIONAL_OBJC_LIBS = -lGLU -lGL -lSDL -lpthread -lSDL_mixer -lSDL_image -lgnustep-base
	ADDITIONAL_CFLAGS = -DLINUX -DNEED_STRLCPY `sdl-config --cflags`
	ADDITIONAL_OBJCFLAGS = -DLOADSAVEGUI -DLINUX -DHAVE_SOUND -Wno-import `sdl-config --cflags`
	oolite_LIB_DIRS += -L/usr/X11R6/lib/
endif
OBJC_PROGRAM_NAME = oolite

oolite_C_FILES = vector.c legacy_random.c strlcpy.c
oolite_OBJC_FILES = Equipment.m EquipmentDictionary.m ScriptEngine.m OXPScript.m Comparison.m AI.m DustEntity.m Entity.m GameController.m GuiDisplayGen.m HeadUpDisplay.m main.m MyOpenGLView.m OpenGLSprite.m ParticleEntity.m PlanetEntity.m PlayerEntityAdditions.m PlayerEntityContracts.m PlayerEntityControls.m PlayerEntitySound.m PlayerEntity.m ResourceManager.m RingEntity.m ShipEntityAI.m ShipEntity.m SkyEntity.m StationEntity.m TextureStore.m Universe.m OOSound.m OOMusic.m SDLImage.m LoadSave.m OOFileManager.m JoystickHandler.m PlayerEntity_StickMapper.m OOBasicSoundReferencePoint.m OOBasicSoundSource.m OOCharacter.m OOTrumble.m WormholeEntity.m ScannerExtension.m OOXMLExtensions.m MutableDictionaryExtension.m Geometry.m Octree.m CollisionRegion.m OOColor.m ScriptCompiler.m StringTokeniser.m

include $(GNUSTEP_MAKEFILES)/objc.make
include GNUmakefile.postamble
