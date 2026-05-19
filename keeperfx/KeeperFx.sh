#!/bin/bash
# Below we assign the source of the control folder (which is the PortMaster folder) based on the distro:
# VERSION: 2025-02-08-v2

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt # We source the control.txt file contents here
# The $ESUDO, $directory, $param_device and necessary sdl configuration controller configurations will be sourced from the control.txt file shown [here]

# We source custom mod files from the portmaster folder example mod_jelos.txt which containts pipewire fixes
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

# We pull the controller configs like the correct SDL2 Gamecontrollerdb GUID from the get_controls function from the control.txt file here
get_controls

# We switch to the port's directory location below
GAMEDIR="/$directory/ports/keeperfx"

# Check if original Dungeon Keeper data files exist
if [ ! -d "$GAMEDIR/keeperfx/data" ] || [ ! -f "$GAMEDIR/keeperfx/data/bluepal.dat" ]; then
    echo "ERROR: Original Dungeon Keeper data files not found!"
    echo "Please place your original game files in: $GAMEDIR/keeperfx/data/"
    echo "You need the 'data' folder from the original Dungeon Keeper game."
    sleep 5
    exit 1
fi

# Switch to the game directory
cd "$GAMEDIR/keeperfx" || { echo "ERROR: Cannot cd to $GAMEDIR/keeperfx"; exit 1; }

# Log the execution of the script, the script overwrites itself on each launch
# Use simple redirect if tee with process substitution doesn't work
if exec 1> >(tee "$GAMEDIR/log.txt") 2>&1; then
    :  # Success
else
    # Fallback to simple file redirect
    exec > "$GAMEDIR/log.txt" 2>&1
fi

echo "Script started at $(date)"

# KeeperFX keeps saves in its own directory, so no special folder mapping needed
# Config files are in config/ and saves in save/ subdirectories of GAMEDIR 

# Port specific additional libraries should be included within the port's directory in a separate subfolder named libs.aarch64, libs.armhf or libs.x64
LIBDIR="$GAMEDIR/keeperfx/libs.${DEVICE_ARCH}"

# Use libraries directly from LIBDIR instead of copying


# Create symlinks for library version mismatches in LIBDIR if needed
if [ -d "$LIBDIR" ]; then
    cd "$LIBDIR"
    for lib in libavcodec.so.58.* libavformat.so.58.* libavutil.so.56.* libswresample.so.3.*; do
        [ -e "$lib" ] || continue
        base=$(echo "$lib" | sed 's/\.[0-9]*$//')
        [ -e "$base" ] || ln -sf "$lib" "$base" 2>/dev/null
    done

    # Create SDL2 base symlinks if needed
    for lib in libSDL2-2.0.so.0.* libSDL2_mixer-2.0.so.0.* libSDL2_net-2.0.so.0.*; do
        [ -e "$lib" ] || continue
        base=$(echo "$lib" | sed 's/\.[0-9]*$//')
        [ -e "$base" ] || ln -sf "$lib" "$base" 2>/dev/null
    done
    cd "$GAMEDIR/keeperfx"
fi

# CRITICAL: Copy SDL2 libraries to current directory
# System SDL2/SDL2_mixer may have version mismatches - bundled versions MUST be used
for lib in libSDL2-2.0.so.0* libSDL2_mixer-2.0.so.0* libSDL2_net-2.0.so.0*; do
    [ -e "$LIBDIR/$lib" ] || continue
    cp "$LIBDIR/$lib" ./ 2>/dev/null
done

# Use ABSOLUTE paths for LD_LIBRARY_PATH
export LD_LIBRARY_PATH=".:$LIBDIR:$LD_LIBRARY_PATH"
# Detect or map architecture to binary name
BINARY_ARCH="${DEVICE_ARCH}"
case "${DEVICE_ARCH}" in
  aarch64|arm64|armv8)
    BINARY_ARCH="aarch64"
    ;;
  armhf|armv7|arm)
    BINARY_ARCH="armhf"
    ;;
  x86_64|x64)
    BINARY_ARCH="x64"
    ;;
esac

# Check which binary exists
if [ -f "./keeperfx.${BINARY_ARCH}" ]; then
    BINARY="./keeperfx.${BINARY_ARCH}"
elif [ -f "./keeperfx-arm64" ]; then
    BINARY="./keeperfx-arm64"
elif [ -f "./keeperfx" ]; then
    BINARY="./keeperfx"
else
    echo "ERROR: No keeperfx binary found!"
    echo "Searched for:"
    echo "  ./keeperfx.${BINARY_ARCH}"
    echo "  ./keeperfx-arm64"
    echo "  ./keeperfx"
    echo "Available files:"
    ls -la | grep -E 'keeperfx|^-rw|^-rwx' | head -20
    sleep 5
    exit 1
fi

# Test if binary is executable
if [ ! -x "$BINARY" ]; then
    chmod +x "$BINARY"
fi

# Provide appropriate controller configuration - KeeperFX has native SDL input support
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Let SDL2 auto-detect the best video backend
# Common options: kmsdrm (modern), fbcon (legacy framebuffer), directfb
# If auto-detection fails, try: export SDL_VIDEODRIVER=fbcon
# For now, let SDL choose automatically by not setting it
unset SDL_VIDEODRIVER

echo "Launching KeeperFX..."

# Now we launch KeeperFX - explicitly pass LD_LIBRARY_PATH through sudo using env
if [ -n "$ESUDO" ]; then
    # sudo drops LD_LIBRARY_PATH, so we use env to set it
    $ESUDO env LD_LIBRARY_PATH="$LD_LIBRARY_PATH" "$BINARY"
else
    "$BINARY"
fi

LAUNCH_EXIT=$?
echo "KeeperFX exited with code: $LAUNCH_EXIT"

exit $LAUNCH_EXIT