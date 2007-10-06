include $(GNUSTEP_MAKEFILES)/common.make
CP = cp
BUILD_WITH_DEBUG_FUNCTIONALITY = yes
vpath %.m src/SDL:src/Core:src/Core/Entities:src/Core/Materials:src/Core/Scripting:src/Core/OXPVerifier
vpath %.h src/SDL:src/Core:src/Core/Entities:src/Core/Materials:src/Core/Scripting:src/Core/OXPVerifier
vpath %.c src/SDL:src/Core:src/BSDCompat
GNUSTEP_INSTALLATION_DIR = $(GNUSTEP_USER_ROOT)
ifeq ($(GNUSTEP_HOST_OS),mingw32)
	ADDITIONAL_INCLUDE_DIRS = -Ideps/Windows-x86-deps/include -Isrc/SDL -Isrc/Core -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities -Isrc/Core/OXPVerifier -Isrc/Debug
	ADDITIONAL_OBJC_LIBS = -lglu32 -lopengl32 -lpng13 -lmingw32 -lSDLmain -lSDL -lSDL_mixer -lgnustep-base -ljs32
	ADDITIONAL_CFLAGS = -DLINUX -DWIN32 -DNEED_STRLCPY `sdl-config --cflags`
# note the vpath stuff above isn't working for me, so adding src/SDL and src/Core explicitly
	ADDITIONAL_OBJCFLAGS = -DLOADSAVEGUI -DLINUX -DWIN32 -DXP_WIN -Wno-import `sdl-config --cflags`
ifeq ($(BUILD_WITH_DEBUG_FUNCTIONALITY),no)
	ADDITIONAL_CFLAGS += -DNDEBUG
	ADDITIONAL_OBJCFLAGS += -DNDEBUG
endif
	oolite_LIB_DIRS += -L/usr/local/lib -L$(GNUSTEP_LOCAL_ROOT)/lib -Ldeps/Windows-x86-deps/lib
else
	ADDITIONAL_INCLUDE_DIRS = -I/usr/include/mozjs -Isrc/SDL -Isrc/Core -Isrc/BSDCompat -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities -Isrc/Core/OXPVerifier -Isrc/Debug
	ADDITIONAL_OBJC_LIBS = -lpng -ljs -lGLU -lGL -lSDL -lpthread -lSDL_mixer -lgnustep-base
	ADDITIONAL_CFLAGS = -DLINUX -DNEED_STRLCPY `sdl-config --cflags`
	ADDITIONAL_OBJCFLAGS = -DLOADSAVEGUI -DLINUX -DXP_UNIX -Wno-import `sdl-config --cflags`
	oolite_LIB_DIRS += -L/usr/X11R6/lib/
endif
OBJC_PROGRAM_NAME = oolite

oolite_C_FILES = legacy_random.c strlcpy.c
oolite_OBJC_FILES = Comparison.m AI.m DustEntity.m Entity.m GameController.m GuiDisplayGen.m HeadUpDisplay.m main.m MyOpenGLView.m OpenGLSprite.m ParticleEntity.m PlanetEntity.m PlayerEntityLegacyScriptEngine.m PlayerEntityContracts.m PlayerEntityControls.m PlayerEntityLoadSave.m PlayerEntitySound.m PlayerEntity.m ResourceManager.m RingEntity.m ShipEntityAI.m ShipEntity.m SkyEntity.m StationEntity.m Universe.m OOSound.m SDLMusic.m NSFileManagerOOExtensions.m JoystickHandler.m PlayerEntityStickMapper.m OOBasicSoundReferencePoint.m OOBasicSoundSource.m OOCharacter.m OOTrumble.m WormholeEntity.m NSScannerOOExtensions.m OOXMLExtensions.m NSMutableDictionaryOOExtensions.m Geometry.m Octree.m CollisionRegion.m OOColor.m OOLogging.m OOCacheManager.m OOCache.m OOStringParsing.m OOCollectionExtractors.m OOVector.m OOMatrix.m OOQuaternion.m OOVoxel.m OOTriangle.m OOPListParsing.m OOFastArithmetic.m OOTextureScaling.m OOConstToString.m OOScript.m OOJSScript.m OOJavaScriptEngine.m OOPListScript.m NSStringOOExtensions.m PlayerEntityScriptMethods.m OOWeakReference.m OOJSEntity.m EntityOOJavaScriptExtensions.m OOJSQuaternion.m OOMaterial.m OOShaderMaterial.m OOShaderProgram.m OOShaderUniform.m OOTexture.m OOTextureLoader.m OOPNGTextureLoader.m OOOpenGLExtensionManager.m OOBasicMaterial.m OOSingleTextureMaterial.m OOCPUInfo.m OOSelfDrawingEntity.m OOEntityWithDrawable.m OODrawable.m OOJSVector.m OOMesh.m OOOpenGL.m OOGraphicsResetManager.m OOProbabilisticTextureManager.m OODebugGLDrawing.m OOShaderUniformMethodType.m OOAsyncQueue.m TextureStore.m OOOXPVerifier.m OOOXPVerifierStage.m OOFileScannerVerifierStage.m OOCheckRequiresPListVerifierStage.m OOCheckDemoShipsPListVerifierStage.m OOCheckEquipmentPListVerifierStage.m OOTextureVerifierStage.m OOModelVerifierStage.m OOCheckShipDataPListVerifierStage.m OOPListSchemaVerifier.m OOJSShip.m OOJSPlayer.m OOJSCall.m OOJSStation.m OOJSSystem.m OOLegacyEventHandlerScript.m OOJSOolite.m OORoleSet.m OOJSGlobal.m OOJSMissionVariables.m OOJSMission.m OOPriorityQueue.m OOScriptTimer.m OOJSTimer.m OOJSClock.m OODebugSupport.m OODebugMonitor.m OOJSConsole.m OODebugTCPConsoleClient.m OOTCPStreamDecoder.c OOTCPStreamDecoderAbstractionLayer.m

include $(GNUSTEP_MAKEFILES)/objc.make
include GNUmakefile.postamble
