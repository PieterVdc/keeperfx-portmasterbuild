#!/bin/bash
# Below we assign the source of the control folder (which is the PortMaster folder) based on the distro:
# VERSION: 2025-02-08-v2

echo 'core.%e.%p' | sudo tee /proc/sys/kernel/core_pattern
sudo sysctl -w kernel.core_uses_pid=1

export KEEPERFX_NO_SUDO=1

# EMERGENCY DEBUG: Write to a temp file to see if script even starts
echo "KeeperFX launcher VERSION 2025-02-08-v2 started at $(date)" > /tmp/keeperfx_startup.log
echo "Args: $@" >> /tmp/keeperfx_startup.log
echo "Script path: $0" >> /tmp/keeperfx_startup.log

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

echo "Control folder: $controlfolder" >> /tmp/keeperfx_startup.log

source $controlfolder/control.txt # We source the control.txt file contents here
# The $ESUDO, $directory, $param_device and necessary sdl configuration controller configurations will be sourced from the control.txt file shown [here]

echo "Sourced control.txt" >> /tmp/keeperfx_startup.log

# We source custom mod files from the portmaster folder example mod_jelos.txt which containts pipewire fixes
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

# We pull the controller configs like the correct SDL2 Gamecontrollerdb GUID from the get_controls function from the control.txt file here
get_controls

# We switch to the port's directory location below
GAMEDIR="/$directory/ports/keeperfx"

echo "GAMEDIR set to: $GAMEDIR" >> /tmp/keeperfx_startup.log
echo "Checking if $GAMEDIR exists..." >> /tmp/keeperfx_startup.log
ls -la "$GAMEDIR" >> /tmp/keeperfx_startup.log 2>&1

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

# Fallback to generic libs folder if arch-specific doesn't exist
if [ ! -d "$LIBDIR" ] && [ -d "$GAMEDIR/keeperfx/libs" ]; then
    echo "Using generic libs folder (libs.${DEVICE_ARCH} not found)"
    LIBDIR="$GAMEDIR/keeperfx/libs"
fi

echo "=== DEBUG INFO ==="
echo "GAMEDIR: $GAMEDIR"
echo "DEVICE_ARCH: $DEVICE_ARCH"
echo "LIBDIR: $LIBDIR"
echo "Current directory: $(pwd)"
echo "Directory contents:"
ls -la "$LIBDIR" | head -20
echo ""

# Use libraries directly from LIBDIR instead of copying
echo "Using libraries from: $LIBDIR"

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

echo "Libraries in $LIBDIR:"
ls -la "$LIBDIR"/*.so* 2>/dev/null | head -20
echo ""

# CRITICAL: Copy SDL2 libraries to current directory
# System SDL2/SDL2_mixer may have version mismatches - bundled versions MUST be used
echo "=== Copying critical SDL2 libraries to current directory ==="
for lib in libSDL2-2.0.so.0* libSDL2_mixer-2.0.so.0* libSDL2_net-2.0.so.0*; do
    [ -e "$LIBDIR/$lib" ] || continue
    cp "$LIBDIR/$lib" ./ 2>/dev/null && echo "✓ Copied $lib" || echo "❌ Failed to copy $lib"
done
echo ""

# Use ABSOLUTE paths for LD_LIBRARY_PATH
export LD_LIBRARY_PATH=".:$LIBDIR:$LD_LIBRARY_PATH"
echo "LD_LIBRARY_PATH set to: $LD_LIBRARY_PATH"
echo ""
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

echo "Detected binary architecture: $BINARY_ARCH"

# Check which binary exists
if [ -f "./keeperfx.${BINARY_ARCH}" ]; then
    BINARY="./keeperfx.${BINARY_ARCH}"
    echo "Found: $BINARY"
elif [ -f "./keeperfx-arm64" ]; then
    BINARY="./keeperfx-arm64"
    echo "Found: $BINARY (migrating from docker build)"
elif [ -f "./keeperfx" ]; then
    BINARY="./keeperfx"
    echo "Found: $BINARY"
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

echo "=== END DEBUG INFO ==="
echo ""

# Test if binary is executable
if [ ! -x "$BINARY" ]; then
    echo "Making $BINARY executable..."
    chmod +x "$BINARY"
fi

# === EXTENSIVE DEBUGGING ===
echo "=== BINARY VERIFICATION ==="
file "$BINARY"
ls -lh "$BINARY"
echo ""
echo "Binary architecture check:"
if command -v readelf >/dev/null 2>&1; then
    readelf -h "$BINARY" 2>/dev/null | grep -E "Class:|Machine:" || echo "  (readelf failed)"
else
    echo "  (readelf not available)"
fi
echo ""

echo "=== CHECKING LIBRARY DEPENDENCIES ==="
echo "Running ldd on binary..."
ldd "$BINARY" 2>&1 | tee /tmp/keeperfx_ldd.txt
echo ""

NOT_FOUND=$(grep "not found" /tmp/keeperfx_ldd.txt | wc -l)
if [ "$NOT_FOUND" -gt 0 ]; then
    echo "❌ WARNING: $NOT_FOUND missing libraries detected:"
    grep "not found" /tmp/keeperfx_ldd.txt
    echo ""
    echo "Attempting to locate missing libraries..."
    grep "not found" /tmp/keeperfx_ldd.txt | awk '{print $1}' | while read lib; do
        echo "  Searching for $lib:"
        find "$LIBDIR" /lib /usr/lib -name "$lib*" 2>/dev/null | head -3
    done
    echo ""
else
    echo "✓ All libraries found by ldd"
fi
echo ""

echo "=== VERIFYING CRITICAL SDL2 LIBRARIES ==="
for sdllib in libSDL2-2.0.so.0 libSDL2_mixer-2.0.so.0 libSDL2_net-2.0.so.0; do
    if [ -f "./$sdllib" ]; then
        echo "✓ Found in current dir: $sdllib"
        ls -lh "./$sdllib"
        # Try to get version info
        strings "./$sdllib" 2>/dev/null | grep -E "^SDL.*version|^2\.[0-9]\.[0-9]" | head -3
    elif [ -f "$LIBDIR/$sdllib" ]; then
        echo "⚠ Found in LIBDIR (not copied?): $sdllib"
    else
        echo "❌ MISSING: $sdllib"
        # Check system libraries
        echo "  Checking system paths..."
        find /lib /usr/lib -name "$sdllib*" 2>/dev/null | head -2
    fi
done
echo ""

echo "=== ENVIRONMENT CHECK ==="
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
echo "PWD=$(pwd)"
echo "USER=$(whoami)"
echo "DEVICE: $DEVICE_ARCH"
echo ""
echo "System SDL2 version (if any):"
find /lib /usr/lib -name "libSDL2-2.0.so.0*" 2>/dev/null | while read syssdl; do
    echo "  $syssdl:"
    strings "$syssdl" 2>/dev/null | grep "SDL-" | head -1
done
echo ""
echo "Available .so files in current directory:"
ls -1 *.so* 2>/dev/null | head -30
echo ""

# Test: try to run binary with --version or --help to check if it works
echo "=== TESTING BINARY EXECUTION ==="
echo "Attempting to run: $BINARY --help"
"$BINARY" --help > /tmp/keeperfx_test.txt 2>&1
TEST_EXIT=$?
echo "Binary test exit code: $TEST_EXIT"
if [ $TEST_EXIT -ne 0 ]; then
    echo "Binary test output:"
    head -30 /tmp/keeperfx_test.txt
    echo ""
    if [ $TEST_EXIT -eq 139 ] || grep -qi "segmentation\|segfault" /tmp/keeperfx_test.txt 2>/dev/null; then
        echo "❌ SEGFAULT DETECTED during test run!"
        echo "This suggests library incompatibility or missing dependencies"
        echo ""
        echo "Checking for mismatched library versions..."
        ldd "$BINARY" | grep -E "SDL2|luajit|spng|avcodec|avformat" | head -10
    fi
fi
echo ""

# Provide appropriate controller configuration - KeeperFX has native SDL input support
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Let SDL2 auto-detect the best video backend
# Common options: kmsdrm (modern), fbcon (legacy framebuffer), directfb
# If auto-detection fails, try: export SDL_VIDEODRIVER=fbcon
# For now, let SDL choose automatically by not setting it
unset SDL_VIDEODRIVER

echo "Launching: $ESUDO $BINARY"
echo "SDL_VIDEODRIVER: (auto-detect)"
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
echo "SDL_GAMECONTROLLERCONFIG=$SDL_GAMECONTROLLERCONFIG"
echo ""

# Enable core dumps for debugging
ulimit -c unlimited
echo "Core dumps enabled (ulimit -c unlimited)"
echo "If crash occurs, check for core file in: $(pwd)"

# Fix core dump pattern to ensure cores are written to current directory
echo "Configuring core dump pattern..."
CURRENT_CORE_PATTERN=$(cat /proc/sys/kernel/core_pattern 2>/dev/null || echo "unknown")
echo "Current core_pattern: $CURRENT_CORE_PATTERN"
if [[ "$CURRENT_CORE_PATTERN" == core* ]] || [[ "$CURRENT_CORE_PATTERN" == "unknown" ]]; then
    echo "✓ Core pattern looks good"
else
    echo "⚠ Core pattern redirects to handler - attempting to fix..."
    echo "core.%e.%p" | sudo tee /proc/sys/kernel/core_pattern 2>/dev/null && echo "✓ Fixed" || echo "❌ Failed (needs sudo access)"
    # Verify it actually changed
    CURRENT_CORE_PATTERN=$(cat /proc/sys/kernel/core_pattern 2>/dev/null || echo "unknown")
    echo "After fix attempt: $CURRENT_CORE_PATTERN"
fi

# Verify ulimit actually worked
ULIMIT_CORE=$(ulimit -c)
echo "ulimit -c reports: $ULIMIT_CORE"
if [ "$ULIMIT_CORE" = "unlimited" ] || [ "$ULIMIT_CORE" -gt 1000000 ]; then
    echo "✓ Core size limit is sufficient"
else
    echo "⚠ Core size limit may be too small: $ULIMIT_CORE"
fi

# Check write permissions
if [ -w "." ]; then
    echo "✓ Current directory is writable"
else
    echo "❌ Current directory is NOT writable - cores cannot be written!"
fi
echo ""

# TEMPORARY DEBUG MODE: Bypass ESUDO to get proper core dumps
# ESUDO prevents core dumps from being written properly
# Set KEEPERFX_USE_SUDO=1 to re-enable ESUDO
echo "=== CORE DUMP DEBUG MODE ==="
if [ "$KEEPERFX_USE_SUDO" = "1" ]; then
    echo "ESUDO enabled (KEEPERFX_USE_SUDO=1)"
    echo "ESUDO is set to: $ESUDO"
elif [ -n "$ESUDO" ]; then
    echo "⚠ TEMPORARILY DISABLING ESUDO for crash debugging"
    echo "Original ESUDO was: $ESUDO"
    echo "(Core dumps don't work under sudo - set KEEPERFX_USE_SUDO=1 to override)"
    ESUDO=""
fi
echo ""

# Final library path verification right before launch
echo "=== PRE-LAUNCH VERIFICATION ==="
echo "Current directory libraries:"
ls -1 ./*.so* 2>/dev/null | wc -l
echo "Symlinks in current directory:"
ls -l ./*.so* 2>/dev/null | grep "^l" | wc -l
echo ""

echo "=== LAUNCHING KEEPERFX ==="

# Check if we can use catchsegv for better crash info
USE_CATCHSEGV=""
if which catchsegv >/dev/null 2>&1; then
    echo "catchsegv available - will capture segfault details"
    USE_CATCHSEGV="catchsegv"
fi

if [ -n "$ESUDO" ]; then
    echo "Command: $ESUDO env LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\" $USE_CATCHSEGV $BINARY"
else
    echo "Command: $USE_CATCHSEGV $BINARY (no sudo)"
fi
echo "Starting at: $(date)"
echo ""

# Now we launch KeeperFX - explicitly pass LD_LIBRARY_PATH through sudo using env
if [ -n "$ESUDO" ]; then
    # sudo drops LD_LIBRARY_PATH, so we use env to set it
    $ESUDO env LD_LIBRARY_PATH="$LD_LIBRARY_PATH" $USE_CATCHSEGV "$BINARY"
else
    $USE_CATCHSEGV "$BINARY"
fi

LAUNCH_EXIT=$?
echo ""
echo "=== LAUNCH EXITED ==="
echo "Exit code: $LAUNCH_EXIT"
if [ $LAUNCH_EXIT -eq 139 ]; then
    echo "❌ Exit code 139 = SEGMENTATION FAULT"
    echo ""
    echo "Checking for core dump..."
    CORE_FILE=""
    if [ -f core ]; then
        CORE_FILE="core"
    elif compgen -G "core.*" > /dev/null; then
        CORE_FILE=$(ls -t core.* 2>/dev/null | head -1)
    fi
    
    if [ -n "$CORE_FILE" ]; then
        CORE_SIZE=$(stat -c%s "$CORE_FILE" 2>/dev/null || echo 0)
        if [ "$CORE_SIZE" -eq 0 ]; then
            echo "❌ Core dump is EMPTY (0 bytes): $CORE_FILE"
            echo ""
            echo "This usually means:"
            echo "  1. Core pattern is piping to a handler that failed"
            echo "  2. Insufficient permissions to write core"
            echo "  3. Disk space issue"
            echo ""
            echo "To fix, try running these commands on the device:"
            echo "  echo 'core.%e.%p' | sudo tee /proc/sys/kernel/core_pattern"
            echo "  sudo sysctl -w kernel.core_uses_pid=1"
            echo ""
            echo "Or set KEEPERFX_NO_SUDO=1 and run without sudo:"
            echo "  export KEEPERFX_NO_SUDO=1"
        else
            echo "✓ Core dump found: $(ls -lh "$CORE_FILE")"
            echo "Analyzing with gdb (if available)..."
            if which gdb >/dev/null 2>&1; then
                echo ""
                echo "Quick backtrace:"
                gdb -batch -ex "bt" "$BINARY" "$CORE_FILE" 2>&1 | tail -30
                echo ""
                echo "For full analysis: gdb $BINARY $CORE_FILE"
                echo "Then type 'bt full' for detailed backtrace"
            else
                echo "gdb not available - copy core to PC for analysis"
                echo "  gdb-multiarch $BINARY $CORE_FILE"
            fi
        fi
    else
        echo "❌ No core dump found"
        echo "Check: cat /proc/sys/kernel/core_pattern"
        echo "If it starts with '|', cores are piped to a handler"
    fi
    echo ""
    echo "=== SEGFAULT TROUBLESHOOTING ==="
    echo "Common causes:"
    echo "1. Library version mismatch (check ldd output above)"
    echo "2. Missing transitive dependencies"
    echo "3. SDL2 configuration incompatible with device"
    echo "4. ESUDO environment issues"
    echo ""
    echo "Try running without ESUDO:"
    echo "  LD_LIBRARY_PATH=\".:$LIBDIR:\$LD_LIBRARY_PATH\" ./$BINARY -nosound"
fi

exit $LAUNCH_EXIT