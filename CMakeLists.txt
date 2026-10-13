cmake_minimum_required(VERSION 3.6.3...3.10)

project(SRR2)

set(SRR2_TITLE "Simpsons Hit & Run")
set(SRR2_VERSION "00.61")
set(SRR2_FILENAME "Simpsons")
set(SRR2_REGION "NTSC" CACHE STRING "Select PAL for the EFIGS multi-language version")
set_property(CACHE SRR2_REGION PROPERTY STRINGS "NTSC" "PAL")

option(SRR2_USE_DLMALLOC "Use Doug Lea's memory allocator for fixed-size heaps" OFF)
option(SRR2_REROUTE_ALL_HEAP_ALLOCATIONS "Reroute all memory allocations by new operator to internal heaps" OFF)
option(SRR2_USE_BINK "Use RAD Game Tools Bink SDK instead of FFmpeg" OFF)
option(SRR2_BUILD_TESTS "Build sample programs for internal libraries" ON)
option(SRR2_MICROPROFILE "Use microprofile instead of the internal profiler" OFF)
option(SRR2_P3D_CG "Use CG shaders rather than GLSL for OpenGL ES" OFF)
set(SRR2_P3D_PDDI "OpenGL" CACHE STRING "Pure3D PDDI implementation")
if(VITA)
	option(SRR2_USE_VITAGL "Use VitaGL as an OpenGL (ES) implementation" ON)
	set_property(CACHE SRR2_P3D_PDDI PROPERTY STRINGS "OpenGL" "GLES1" "GLES2" "GXM")
else()
	set_property(CACHE SRR2_P3D_PDDI PROPERTY STRINGS "OpenGL" "GLES1" "GLES2")
endif()

if(VITA)
	include("${VITASDK}/share/vita.cmake" REQUIRED)

	add_definitions(-DRAD_VITA)
	## Configuration options for this app
	# Display name (under bubble in LiveArea)
	set(VITA_APP_NAME ${SRR2_TITLE})
	# Unique ID must be exactly 9 characters. Recommended: XXXXYYYYY where X =
	# unique string of developer and Y = a unique number for this app
	set(VITA_TITLEID  "ROADRAGE2")
	# Optional version string to show in LiveArea's more info screen
	set(VITA_VERSION ${SRR2_VERSION})
endif()

if(APPLE)
	# Prefer OpenAL Soft over Apple's deprecated OpenAL framework
	set(CMAKE_FIND_FRAMEWORK LAST)

	# The app icon is compiled by the app-icon recipe in the justfile, its name is used
	# by the Info.plist templates
	find_program(SRR2_JUST just REQUIRED)
	set(SRR2_APP_ICON "${CMAKE_SOURCE_DIR}/ios/icon/Simpsons Hit and Run.icon")
	# The name in the menu bar and the Dock on macOS, the Dock uses the name of
	# the app file otherwise. Substituted into Info.plist unescaped.
	set(SRR2_MACOS_TITLE "The Simpsons: Hit &amp; Run")
	get_filename_component(SRR2_APP_ICON_NAME "${SRR2_APP_ICON}" NAME_WE)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
	add_definitions(-DRAD_IOS)
	# iOS only supports OpenGL ES
	set(SRR2_P3D_PDDI "GLES2" CACHE STRING "Pure3D PDDI implementation" FORCE)
	set(SRR2_BUILD_TESTS OFF CACHE BOOL "Build sample programs for internal libraries" FORCE)
	set(SRR2_IOS_TEAM_ID "" CACHE STRING "Apple development team ID used to sign the iOS app")
	set(SRR2_IOS_BUNDLE_ID "com.freeradical.hitandrun" CACHE STRING "iOS app bundle identifier")
	# Substituted into ios/Info.plist.in
	if(CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
		set(SRR2_IOS_PLATFORM "iPhoneSimulator")
	else()
		set(SRR2_IOS_PLATFORM "iPhoneOS")
	endif()
endif()

find_program(CCACHE_FOUND ccache)
if(CCACHE_FOUND)
    set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE ccache)
endif()

if(NOT VITA)
	find_package(SDL3)
endif()
if(SDL3_FOUND)
	get_target_property(SDL_INCLUDE_DIR SDL3::Headers INTERFACE_INCLUDE_DIRECTORIES)
	include_directories(${SDL_INCLUDE_DIR}/SDL3)
	set(SDL_LIBRARY SDL3::SDL3)
else()
	find_package(SDL2 REQUIRED)
	set(SDL_LIBRARY SDL2::SDL2 SDL2::SDL2main)
endif()
find_package(PNG REQUIRED)
if(APPLE AND TARGET ZLIB::ZLIB)
	# PNG needs zlib, which is in the SDK. FindZLIB adds the SDK's usr/include as
	# a system include directory, it gets searched before libc++'s headers and
	# breaks <cmath>. The SDK is searched anyway.
	set_property(TARGET ZLIB::ZLIB PROPERTY INTERFACE_INCLUDE_DIRECTORIES "")
endif()
set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)
find_package(OpenAL REQUIRED)

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
	add_compile_options(-fvisibility=hidden)
	if(CMAKE_BUILD_TYPE STREQUAL "Debug")
		add_compile_options(
			-Werror
			-ggdb
		)
	endif()
	if(VITA)
		add_compile_options(
			-mtune=cortex-a9
			-mfpu=neon
		)
	endif()
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
	add_definitions(-DRAD_DEBUG)
else()
	add_definitions(-DRAD_RELEASE)
endif()

add_definitions(
	-DRAD_CONSOLE
	-DRAD_WIN32
	-DRAD_SDL
)

if(SRR2_REGION STREQUAL "PAL")
	add_definitions(-DPAL)
endif()
if(SRR2_USE_DLMALLOC)
	add_definitions(-DUSE_DOUG_LEA_HEAP)
endif()
if(SRR2_REROUTE_ALL_HEAP_ALLOCATIONS)
	add_definitions(-DREROUTE_ALL_HEAP_ALLOCATIONS)
endif()
if(SRR2_USE_BINK)
	add_definitions(-DRAD_MOVIEPLAYER_USE_BINK)
else()
	find_package(PkgConfig REQUIRED)
	pkg_check_modules(FFmpeg REQUIRED IMPORTED_TARGET
			libavformat
			libavcodec
			libavutil
			libswresample
			libswscale
	)
endif()
if(SRR2_MICROPROFILE)
	add_definitions(-DMICROPROFILE_ENABLED)
endif()
if(SRR2_P3D_CG)
	add_definitions(-DRAD_CG)
endif()
if(SRR2_USE_VITAGL)
    add_definitions(-DRAD_VITAGL)
endif()
if(SRR2_P3D_PDDI STREQUAL "GXM")
    add_definitions(-DRAD_GXM)
endif()
if(SRR2_P3D_PDDI STREQUAL "GLES1")
	add_definitions(-DRAD_GLES)
	add_definitions(-DRAD_GLES_VERSION=1)
endif()
if(SRR2_P3D_PDDI STREQUAL "GLES2")
	add_definitions(-DRAD_GLES)
	add_definitions(-DRAD_GLES_VERSION=2)
endif()

if(WIN32)
	add_definitions(-D_CRT_SECURE_NO_WARNINGS)
endif()

add_subdirectory(libs)
add_subdirectory(code)

if(VITA)
	## Create Vita files
	if(SRR2_P3D_PDDI STREQUAL "GLES2" AND NOT SRR2_USE_VITAGL)
		vita_create_self(${PROJECT_NAME}.self code/${PROJECT_NAME} UNSAFE)
		# The FILE directive lets you add additional files to the VPK, the syntax is
		# FILE src_path dst_path_in_vpk. In this case, we add the LiveArea paths.
		vita_create_vpk(${SRR2_FILENAME}${SRR2_REGION}.vpk ${VITA_TITLEID} ${PROJECT_NAME}.self
			VERSION ${VITA_VERSION}
			NAME ${VITA_APP_NAME}
			FILE sce_sys/icon0.png sce_sys/icon0.png
			sce_sys/livearea/contents/bg.png sce_sys/livearea/contents/bg.png
			sce_sys/livearea/contents/startup.png sce_sys/livearea/contents/startup.png
			sce_sys/livearea/contents/template.xml sce_sys/livearea/contents/template.xml
			art art

			#suprx
			module/libGLESv2.suprx module/libGLESv2.suprx
			module/libgpu_es4_ext.suprx module/libgpu_es4_ext.suprx
			module/libIMGEGL.suprx module/libIMGEGL.suprx
			module/libpvrPSP2_WSEGL.suprx module/libpvrPSP2_WSEGL.suprx
		)
	else()
		vita_create_self(${PROJECT_NAME}.self code/${PROJECT_NAME})
		# The FILE directive lets you add additional files to the VPK, the syntax is
		# FILE src_path dst_path_in_vpk. In this case, we add the LiveArea paths.
		vita_create_vpk(${SRR2_FILENAME}${SRR2_REGION}.vpk ${VITA_TITLEID} ${PROJECT_NAME}.self
			VERSION ${VITA_VERSION}
			NAME ${VITA_APP_NAME}
			FILE sce_sys/icon0.png sce_sys/icon0.png
			sce_sys/livearea/contents/bg.png sce_sys/livearea/contents/bg.png
			sce_sys/livearea/contents/startup.png sce_sys/livearea/contents/startup.png
			sce_sys/livearea/contents/template.xml sce_sys/livearea/contents/template.xml
			art art

			#gxp
			libs/pure3d/pddi/gxm/shaders/vertex_cg.gxp shaders/vertex_cg.gxp
			libs/pure3d/pddi/gxm/shaders/color_cg.gxp shaders/color_cg.gxp
			libs/pure3d/pddi/gxm/shaders/texture_cg.gxp shaders/texture_cg.gxp
			libs/pure3d/pddi/gxm/shaders/alpha_cg.gxp shaders/alpha_cg.gxp
		)
	endif()
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "NintendoSwitch")
	nx_generate_nacp(OUTPUT ${PROJECT_NAME}.nacp
		NAME ${SRR2_TITLE}
		AUTHOR "Radical Entertainment"
		VERSION ${SRR2_VERSION}
	)
	nx_create_nro(code/${PROJECT_NAME}
		OUTPUT ${SRR2_FILENAME}${SRR2_REGION}.nro
		ICON ${PROJECT_NAME}.jpg
		NACP ${PROJECT_NAME}.nacp
		ROMFS romfs
	)
endif()

if(APPLE)
	# The title is substituted into Info.plist unescaped
	string(REPLACE "&" "&amp;" SRR2_PLIST_TITLE "${SRR2_TITLE}")
	set_target_properties(${PROJECT_NAME} PROPERTIES
		MACOSX_BUNDLE TRUE
		OUTPUT_NAME ${SRR2_FILENAME}
		MACOSX_BUNDLE_BUNDLE_NAME "${SRR2_PLIST_TITLE}"
		MACOSX_BUNDLE_GUI_IDENTIFIER "com.freeradical.hitandrun"
		XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.freeradical.hitandrun"
		MACOSX_BUNDLE_BUNDLE_VERSION ${SRR2_VERSION}
		MACOSX_BUNDLE_SHORT_VERSION_STRING ${SRR2_VERSION}
	)
	if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
		set_target_properties(${PROJECT_NAME} PROPERTIES
			MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/ios/Info.plist.in"
			MACOSX_BUNDLE_GUI_IDENTIFIER "${SRR2_IOS_BUNDLE_ID}"
			XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${SRR2_IOS_BUNDLE_ID}"
			XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
			XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "15.0"
			XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic"
			XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "Apple Development"
			XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${SRR2_IOS_TEAM_ID}"
		)
	else()
		set_target_properties(${PROJECT_NAME} PROPERTIES
			OUTPUT_NAME "Simpsons Hit and Run"
			MACOSX_BUNDLE_BUNDLE_NAME "${SRR2_MACOS_TITLE}"
			MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/macos/Info.plist.in"
			MACOSX_BUNDLE_ICON_FILE "${SRR2_APP_ICON_NAME}"
		)
		target_sources(${PROJECT_NAME} PRIVATE "${CMAKE_SOURCE_DIR}/macos/en.lproj/InfoPlist.strings")
		set_source_files_properties("${CMAKE_SOURCE_DIR}/macos/en.lproj/InfoPlist.strings"
			TARGET_DIRECTORY ${PROJECT_NAME}
			PROPERTIES MACOSX_PACKAGE_LOCATION Resources/en.lproj
		)
	endif()

	# Compile the app icon from the Icon Composer file with Xcode's asset
	# compiler and add the result to the bundle as resources. The files are
	# generated in the build directory, the game depends on the target that
	# generates them. Setting the properties of a source file of a target in
	# another directory needs CMake 3.18.
	if(CMAKE_VERSION VERSION_LESS 3.18)
		message(FATAL_ERROR "CMake 3.18 or newer is needed to build for Apple platforms")
	endif()
	set(SRR2_ICON_DIR "${CMAKE_BINARY_DIR}/icon")
	if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
		string(TOLOWER "${SRR2_IOS_PLATFORM}" SRR2_ICON_PLATFORM)
		set(SRR2_ICON_MIN_VERSION "${CMAKE_OSX_DEPLOYMENT_TARGET}")
		set(SRR2_ICON_DEVICES iphone ipad)
		set(SRR2_ICON_FILES
			"${SRR2_ICON_DIR}/Assets.car"
			"${SRR2_ICON_DIR}/${SRR2_APP_ICON_NAME}60x60@2x.png"
			"${SRR2_ICON_DIR}/${SRR2_APP_ICON_NAME}76x76@2x~ipad.png"
		)
	else()
		set(SRR2_ICON_PLATFORM macosx)
		set(SRR2_ICON_MIN_VERSION "11.0")
		set(SRR2_ICON_DEVICES mac)
		set(SRR2_ICON_FILES
			"${SRR2_ICON_DIR}/Assets.car"
			"${SRR2_ICON_DIR}/${SRR2_APP_ICON_NAME}.icns"
		)
	endif()
	file(GLOB_RECURSE SRR2_APP_ICON_SOURCES "${SRR2_APP_ICON}/*")
	add_custom_command(OUTPUT ${SRR2_ICON_FILES}
		COMMAND ${SRR2_JUST} --justfile "${CMAKE_SOURCE_DIR}/justfile" app-icon
			"${SRR2_APP_ICON}" ${SRR2_ICON_PLATFORM} ${SRR2_ICON_MIN_VERSION}
			"${SRR2_ICON_DIR}" ${SRR2_ICON_DEVICES}
		DEPENDS "${CMAKE_SOURCE_DIR}/justfile" ${SRR2_APP_ICON_SOURCES}
		VERBATIM
	)
	add_custom_target(${PROJECT_NAME}_icon DEPENDS ${SRR2_ICON_FILES})
	add_dependencies(${PROJECT_NAME} ${PROJECT_NAME}_icon)
	target_sources(${PROJECT_NAME} PRIVATE ${SRR2_ICON_FILES})
	set_source_files_properties(${SRR2_ICON_FILES}
		TARGET_DIRECTORY ${PROJECT_NAME}
		PROPERTIES GENERATED TRUE MACOSX_PACKAGE_LOCATION Resources
	)
endif()
