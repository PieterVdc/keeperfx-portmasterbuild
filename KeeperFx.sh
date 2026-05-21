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
if [ ! -d "$GAMEDIR/data" ] || [ ! -f "$GAMEDIR/data/bluepal.dat" ]; then
    pm_message "ERROR: Original Dungeon Keeper data files not found!"
    pm_message "Please place following files from the original game files in: $GAMEDIR/data/"
    pm_message "./data/bluepal.dat ./data/bluepall.dat ./data/dogpal.pal./data/hitpall.dat ./data/lightng.pal ./data/main.pal ./data/mapfadeg.dat./data/redpal.col ./data/redpall.dat ./data/slab0-0.dat ./data/slab0-1.dat./data/vampal.pal ./data/whitepal.col"
    pm_message "and these in : $GAMEDIR/sound/"
    pm_message "./sound/atmos1.sbk ./sound/atmos2.sbk ./sound/bullfrog.sbk"

    sleep 5
    exit 1
fi

# Switch to the game directory
cd "$GAMEDIR" || { echo "ERROR: Cannot cd to $GAMEDIR"; exit 1; }

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
LIBDIR="$GAMEDIR/libs.${DEVICE_ARCH}"



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
else
    pm_message "ERROR: No keeperfx binary found!"
    pm_message "Searched for:"
    pm_message "  ./keeperfx.${BINARY_ARCH}"
    pm_message "Available files:"
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