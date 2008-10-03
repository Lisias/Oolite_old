include $(GNUSTEP_MAKEFILES)/common.make
CP = cp
BUILD_WITH_DEBUG_FUNCTIONALITY = yes
vpath %.m src/SDL:src/Core:src/Core/Entities:src/Core/Materials:src/Core/Scripting:src/Core/OXPVerifier:src/Core/Debug
vpath %.h src/SDL:src/Core:src/Core/Entities:src/Core/Materials:src/Core/Scripting:src/Core/OXPVerifier:src/Core/Debug
vpath %.c src/SDL:src/Core:src/BSDCompat:src/Core/Debug
GNUSTEP_INSTALLATION_DIR = $(GNUSTEP_USER_ROOT)
ifeq ($(GNUSTEP_HOST_OS),mingw32)
	ADDITIONAL_INCLUDE_DIRS = -Ideps/Windows-x86-deps/include -Isrc/SDL -Isrc/Core -Isrc/BSDCompat -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities -Isrc/Core/OXPVerifier -Isrc/Core/Debug
	ADDITIONAL_OBJC_LIBS = -lglu32 -lopengl32 -lpng13 -lmingw32 -lSDLmain -lSDL -lSDL_mixer -lgnustep-base -ljs32
	ADDITIONAL_CFLAGS = -DWIN32 -DDOCKING_CLEARANCE_ENABLED -DNEED_STRLCPY `sdl-config --cflags`
# note the vpath stuff above isn't working for me, so adding src/SDL and src/Core explicitly
	ADDITIONAL_OBJCFLAGS = -DLOADSAVEGUI -DWIN32 -DXP_WIN -DDOCKING_CLEARANCE_ENABLED -Wno-import `sdl-config --cflags`
ifeq ($(BUILD_WITH_DEBUG_FUNCTIONALITY),no)
	ADDITIONAL_CFLAGS += -DNDEBUG
	ADDITIONAL_OBJCFLAGS += -DNDEBUG
endif
	oolite_LIB_DIRS += -L/usr/local/lib -L$(GNUSTEP_LOCAL_ROOT)/lib -Ldeps/Windows-x86-deps/lib
else
	ADDITIONAL_INCLUDE_DIRS = -Ideps/Cross-platform-deps/SpiderMonkey/js/src  -Ideps/Cross-platform-deps/SpiderMonkey/js/src/Linux_All_DBG.OBJ -Isrc/SDL -Isrc/Core -Isrc/BSDCompat -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities -Isrc/Core/OXPVerifier -Isrc/Core/Debug
	ADDITIONAL_OBJC_LIBS = -lpng -ljs -lGLU -lGL -lSDL -lpthread -lSDL_mixer -lgnustep-base
	ADDITIONAL_CFLAGS = -DLINUX -DNEED_STRLCPY `sdl-config --cflags`
	ADDITIONAL_OBJCFLAGS = -std=c99 -DLOADSAVEGUI -DLINUX -DXP_UNIX -Wno-import `sdl-config --cflags`
	oolite_LIB_DIRS += -Ldeps/Cross-platform-deps/SpiderMonkey/js/src/Linux_All_DBG.OBJ -L/usr/X11R6/lib/
endif
OBJC_PROGRAM_NAME = oolite

oolite_C_FILES = legacy_random.c strlcpy.c OOTCPStreamDecoder.c
oolite_OBJC_FILES = OOCocoa.m Comparison.m AI.m DustEntity.m Entity.m GameController.m GuiDisplayGen.m HeadUpDisplay.m main.m MyOpenGLView.m OpenGLSprite.m ParticleEntity.m PlanetEntity.m PlayerEntityLegacyScriptEngine.m PlayerEntityContracts.m PlayerEntityControls.m PlayerEntityLoadSave.m PlayerEntitySound.m PlayerEntity.m ResourceManager.m RingEntity.m ShipEntityAI.m ShipEntity.m SkyEntity.m StationEntity.m Universe.m NSFileManagerOOExtensions.m JoystickHandler.m PlayerEntityStickMapper.m OOCharacter.m OOTrumble.m WormholeEntity.m NSScannerOOExtensions.m OOXMLExtensions.m NSMutableDictionaryOOExtensions.m Geometry.m Octree.m CollisionRegion.m OOColor.m OOLogging.m OOCacheManager.m OOCache.m OOStringParsing.m OOCollectionExtractors.m OOVector.m OOMatrix.m OOQuaternion.m OOVoxel.m OOTriangle.m OOPListParsing.m OOFastArithmetic.m OOTextureScaling.m OOConstToString.m OOScript.m OOJSScript.m OOJavaScriptEngine.m OOPListScript.m NSStringOOExtensions.m PlayerEntityScriptMethods.m OOWeakReference.m OOJSEntity.m EntityOOJavaScriptExtensions.m OOJSQuaternion.m OOMaterial.m OOShaderMaterial.m OOShaderProgram.m OOShaderUniform.m OOTexture.m OONullTexture.m OOTextureLoader.m OOPNGTextureLoader.m OOOpenGLExtensionManager.m OOBasicMaterial.m OOSingleTextureMaterial.m OOCPUInfo.m OOSelfDrawingEntity.m OOEntityWithDrawable.m OODrawable.m OOJSVector.m OOMesh.m OOOpenGL.m OOGraphicsResetManager.m OOProbabilisticTextureManager.m OODebugGLDrawing.m OOShaderUniformMethodType.m OOAsyncQueue.m TextureStore.m OOOXPVerifier.m OOOXPVerifierStage.m OOFileScannerVerifierStage.m OOCheckRequiresPListVerifierStage.m OOCheckDemoShipsPListVerifierStage.m OOCheckEquipmentPListVerifierStage.m OOTextureVerifierStage.m OOModelVerifierStage.m OOCheckShipDataPListVerifierStage.m OOPListSchemaVerifier.m OOJSShip.m OOJSPlayer.m OOJSCall.m OOJSStation.m OOJSSystem.m OOLegacyEventHandlerScript.m OOJSOolite.m OORoleSet.m OOJSGlobal.m OOJSMissionVariables.m OOJSMission.m OOPriorityQueue.m OOScriptTimer.m OOJSTimer.m OOJSClock.m OODebugSupport.m OODebugMonitor.m OOJSConsole.m OODebugTCPConsoleClient.m OOTCPStreamDecoderAbstractionLayer.m OOEntityFilterPredicate.m OOJSPlanet.m OOJSWorldScripts.m OOJSSun.m NSThreadOOExtensions.m OOEncodingConverter.m OOJSSound.m OOJSSoundSource.m OOMusicController.m OOLogHeader.m OOJSSpecialFunctions.m OOSpatialReference.m OOSkyDrawable.m OOFilteringEnumerator.m OOSoundSourcePool.m ShipEntityScriptMethods.m OOShipRegistry.m OOProbabilitySet.m OOJSSystemInfo.m NSDictionaryOOExtensions.m OOEquipmentType.m OOCamera.m OOJSPlayerShip.m OOSDLSound.m OOSDLConcreteSound.m OOSoundSource.m OOSDLSoundMixer.m OOSDLSoundChannel.m OOBasicSoundReferencePoint.m SDLMusic.m OOLogOutputHandler.m

include $(GNUSTEP_MAKEFILES)/objc.make
include GNUmakefile.postamble
