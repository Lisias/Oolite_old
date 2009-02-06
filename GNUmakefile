include $(GNUSTEP_MAKEFILES)/common.make
CP = cp
BUILD_WITH_DEBUG_FUNCTIONALITY = yes
vpath %.m src/SDL:src/Core:src/Core/Entities:src/Core/Materials:src/Core/Scripting:src/Core/OXPVerifier:src/Core/Debug
vpath %.h src/SDL:src/Core:src/Core/Entities:src/Core/Materials:src/Core/Scripting:src/Core/OXPVerifier:src/Core/Debug
vpath %.c src/SDL:src/Core:src/BSDCompat:src/Core/Debug
GNUSTEP_INSTALLATION_DIR = $(GNUSTEP_USER_ROOT)
ifeq ($(GNUSTEP_HOST_OS),mingw32)
	ADDITIONAL_INCLUDE_DIRS = -Ideps/Windows-x86-deps/include -Isrc/SDL -Isrc/Core -Isrc/BSDCompat -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities -Isrc/Core/OXPVerifier -Isrc/Core/Debug
	ADDITIONAL_OBJC_LIBS = -lglu32 -lopengl32 -lpng12.dll -lmingw32 -lSDLmain -lSDL -lSDL_mixer -lgnustep-base -ljs32
	ADDITIONAL_CFLAGS = -DWIN32 -DDOCKING_CLEARANCE_ENABLED -DALLOW_PROCEDURAL_PLANETS -DNEED_STRLCPY `sdl-config --cflags`
# note the vpath stuff above isn't working for me, so adding src/SDL and src/Core explicitly
	ADDITIONAL_OBJCFLAGS = -DLOADSAVEGUI -DWIN32 -DXP_WIN -DDOCKING_CLEARANCE_ENABLED -DALLOW_PROCEDURAL_PLANETS -Wno-import `sdl-config --cflags`
	oolite_LIB_DIRS += -L/usr/local/lib -L$(GNUSTEP_LOCAL_ROOT)/lib -Ldeps/Windows-x86-deps/lib
else
	LIBJS_SRC_DIR = deps/Cross-platform-deps/SpiderMonkey/js/src
	LIBJS_BIN_DIR = $(LIBJS_SRC_DIR)/Linux_All_OPT.OBJ
	ADDITIONAL_INCLUDE_DIRS = -I$(LIBJS_SRC_DIR)  -I$(LIBJS_BIN_DIR) -Isrc/SDL -Isrc/Core -Isrc/BSDCompat -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities -Isrc/Core/OXPVerifier -Isrc/Core/Debug
	ADDITIONAL_OBJC_LIBS = -lpng $(LIBJS_BIN_DIR)/libjs.a -lGLU -lGL -lSDL -lSDL_mixer -lgnustep-base
	ADDITIONAL_CFLAGS = -DLINUX -DDOCKING_CLEARANCE_ENABLED -DALLOW_PROCEDURAL_PLANETS -DNEED_STRLCPY `sdl-config --cflags`
	ADDITIONAL_OBJCFLAGS = -std=c99 -DLOADSAVEGUI -DLINUX -DDOCKING_CLEARANCE_ENABLED -DALLOW_PROCEDURAL_PLANETS -DXP_UNIX -Wno-import `sdl-config --cflags`
	oolite_LIB_DIRS += -L/usr/X11R6/lib/
endif
ifeq ($(debug),yes)
	ADDITIONAL_CFLAGS += -g -O0
	ADDITIONAL_OBJCFLAGS += -g -O0
	GNUSTEP_OBJ_DIR_NAME := $(GNUSTEP_OBJ_DIR_NAME).dbg
endif
ifeq ($(BUILD_WITH_DEBUG_FUNCTIONALITY),no)
	ADDITIONAL_CFLAGS += -DNDEBUG
	ADDITIONAL_OBJCFLAGS += -DNDEBUG
endif

OBJC_PROGRAM_NAME = oolite

oolite_C_FILES = \
	legacy_random.c \
	strlcpy.c \
	OOTCPStreamDecoder.c


OOLITE_DEBUG_FILES = \
	OODebugMonitor.m \
	OODebugSupport.m \
	OODebugTCPConsoleClient.m \
	OOJSConsole.m \
	OOTCPStreamDecoderAbstractionLayer.m

OOLITE_ENTITY_FILES = \
	DustEntity.m \
	Entity.m \
	OOEntityWithDrawable.m \
	OOSelfDrawingEntity.m \
	ParticleEntity.m \
	PlanetEntity.m \
	PlayerEntity.m \
	PlayerEntityContracts.m \
	PlayerEntityControls.m \
	PlayerEntityLegacyScriptEngine.m \
	PlayerEntityLoadSave.m \
	PlayerEntityScriptMethods.m \
	PlayerEntitySound.m \
	PlayerEntityStickMapper.m \
	RingEntity.m \
	ShipEntity.m \
	ShipEntityAI.m \
	ShipEntityScriptMethods.m \
	SkyEntity.m \
	StationEntity.m \
	WormholeEntity.m

OOLITE_GRAPHICS_DRAWABLE_FILES = \
	OODrawable.m \
	OOMesh.m

OOLITE_GRAPHICS_MATERIAL_FILES = \
	OOBasicMaterial.m \
	OOMaterial.m \
	OONullTexture.m \
	OOPNGTextureLoader.m \
	OOShaderMaterial.m \
	OOShaderProgram.m \
	OOShaderUniform.m \
	OOShaderUniformMethodType.m \
	OOSingleTextureMaterial.m \
	OOTexture.m \
	OOTextureLoader.m \
	OOTextureScaling.m

OOLITE_GRAPHICS_MISC_FILES = \
	OOCamera.m \
	OOCrosshairs.m \
	OODebugGLDrawing.m \
	OOGraphicsResetManager.m \
	OOLight.m \
	OOOpenGL.m \
	OOOpenGLExtensionManager.m \
	OOProbabilisticTextureManager.m \
	OOSkyDrawable.m \
	OpenGLSprite.m

OOLITE_MATHS_FILES = \
	CollisionRegion.m \
	Geometry.m \
	Octree.m \
	OOFastArithmetic.m \
	OOMatrix.m \
	OOQuaternion.m \
	OOTriangle.m \
	OOVector.m \
	OOVoxel.m

OOLITE_OXP_VERIFIER_FILES = \
	OOAIStateMachineVerifierStage.m \
	OOCheckDemoShipsPListVerifierStage.m \
	OOCheckEquipmentPListVerifierStage.m \
	OOCheckRequiresPListVerifierStage.m \
	OOCheckShipDataPListVerifierStage.m \
	OOFileScannerVerifierStage.m \
	OOModelVerifierStage.m \
	OOOXPVerifier.m \
	OOOXPVerifierStage.m \
	OOPListSchemaVerifier.m \
	OOTextureVerifierStage.m

OOLITE_RSRC_MGMT_FILES = \
	OldSchoolPropertyListWriting.m \
	OOCache.m \
	OOCacheManager.m \
	OOConvertSystemDescriptions.m \
	OOPListParsing.m \
	ResourceManager.m \
	TextureStore.m

OOLITE_SCRIPTING_FILES = \
	EntityOOJavaScriptExtensions.m \
	OOJavaScriptEngine.m \
	OOJSCall.m \
	OOJSClock.m \
	OOJSEntity.m \
	OOJSEquipmentInfo.m \
	OOJSFunction.m \
	OOJSGlobal.m \
	OOJSMission.m \
	OOJSMissionVariables.m \
	OOJSOolite.m \
	OOJSPlanet.m \
	OOJSPlayer.m \
	OOJSPlayerShip.m \
	OOJSQuaternion.m \
	OOJSScript.m \
	OOJSShip.m \
	OOJSShipGroup.m \
	OOJSSound.m \
	OOJSSoundSource.m \
	OOJSSpecialFunctions.m \
	OOJSStation.m \
	OOJSSun.m \
	OOJSSystem.m \
	OOJSSystemInfo.m \
	OOJSTimer.m \
	OOJSVector.m \
	OOJSWorldScripts.m \
	OOLegacyScriptWhitelist.m \
	OOPListScript.m \
	OOScript.m \
	OOScriptTimer.m

OOLITE_SOUND_FILES = \
	OOBasicSoundReferencePoint.m \
	OOMusicController.m \
	OOSDLConcreteSound.m \
	OOSDLSound.m \
	OOSDLSoundChannel.m \
	OOSDLSoundMixer.m \
	OOSoundSource.m \
	OOSoundSourcePool.m \
	SDLMusic.m

OOLITE_UI_FILES = \
	GuiDisplayGen.m \
	HeadUpDisplay.m \
	OOEncodingConverter.m

OO_UTILITY_FILES = \
	Comparison.m \
	NSDictionaryOOExtensions.m \
	NSFileManagerOOExtensions.m \
	NSMutableDictionaryOOExtensions.m \
	NSScannerOOExtensions.m \
	NSStringOOExtensions.m \
	NSThreadOOExtensions.m \
	OOAsyncQueue.m \
	OOCollectionExtractors.m \
	OOColor.m \
	OOConstToString.m \
	OOCPUInfo.m \
	OOEntityFilterPredicate.m \
	OOExcludeObjectEnumerator.m \
	OOFilteringEnumerator.m \
	OOIsNumberLiteral.m \
	OOLogging.m \
	OOLogHeader.m \
	OOLogOutputHandler.m \
	OOPriorityQueue.m \
	OOProbabilitySet.m \
	OOShipGroup.m \
	OOStringParsing.m \
	OOWeakReference.m \
	OOXMLExtensions.m

OOLITE_MISC_FILES = \
	AI.m \
	GameController.m \
	JoystickHandler.m \
	main.m \
	MyOpenGLView.m \
	OOCharacter.m \
	OOCocoa.m \
	OOEquipmentType.m \
	OORoleSet.m \
	OOShipRegistry.m \
	OOSpatialReference.m \
	OOTrumble.m \
	Universe.m

oolite_OBJC_FILES = \
	$(OOLITE_DEBUG_FILES) \
	$(OOLITE_ENTITY_FILES) \
	$(OOLITE_GRAPHICS_DRAWABLE_FILES) \
	$(OOLITE_GRAPHICS_MATERIAL_FILES) \
	$(OOLITE_GRAPHICS_MISC_FILES) \
	$(OOLITE_MATHS_FILES) \
	$(OOLITE_OXP_VERIFIER_FILES) \
	$(OOLITE_RSRC_MGMT_FILES) \
	$(OOLITE_SCRIPTING_FILES) \
	$(OOLITE_SOUND_FILES) \
	$(OOLITE_UI_FILES) \
	$(OO_UTILITY_FILES) \
	$(OOLITE_MISC_FILES)

include $(GNUSTEP_MAKEFILES)/objc.make
include GNUmakefile.postamble
