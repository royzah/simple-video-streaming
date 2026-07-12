#!/bin/bash
# Bulletproof Video Streamer - Works on ANY laptop
# Auto-selects NVIDIA, VA, QuickSync, VA-API, or software H.264 encoding

PORT=${PORT:-5004}
BITRATE=${BITRATE:-3000}

echo "=== Video Streamer ==="
echo ""

# Ask for destination IP
read -rp "Enter destination IP (press Enter for localhost): " DEST_IP
if [ -z "$DEST_IP" ]; then
    DEST_IP="127.0.0.1"
    echo "Using localhost: $DEST_IP"
else
    echo "Using remote IP: $DEST_IP"

    # Test connection for remote IP
    echo "Testing connection..."
    if ! ping -c 2 -W 2 "$DEST_IP" >/dev/null 2>&1; then
        echo "WARNING: Cannot reach $DEST_IP"
        read -rp "Continue anyway? (y/n): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy] ]]; then
            exit 1
        fi
    else
        echo "Connection OK"
    fi
fi

echo ""

# Select source
echo "Select video source:"
echo "  [1] Camera"
echo "  [2] Video file"
echo "  [3] Test pattern"
read -rp "Choice [3]: " SOURCE_CHOICE
SOURCE_CHOICE=${SOURCE_CHOICE:-3}

echo ""

# Encoder candidates in priority order: "type|element|test-format".
# va is the modern VA-API plugin (preferred over legacy vaapi); the viewer's
# decodebin decodes whatever we send, so any of these interoperates.
ENCODERS=(
    "nvidia|nvh264enc|I420"
    "va|vah264enc|NV12"
    "quicksync|qsvh264enc|NV12"
    "vaapi|vaapih264enc|NV12"
)

# Production pipeline fragment for an encoder type (all emit compatible H.264).
encoder_pipeline() {
    case "$1" in
        nvidia)
            echo "videoconvert ! video/x-raw,format=I420 ! nvh264enc preset=low-latency-hq bitrate=$BITRATE"
            ;;
        va)
            echo "videoconvert ! video/x-raw,format=NV12 ! vah264enc bitrate=$BITRATE"
            ;;
        quicksync)
            echo "videoconvert ! video/x-raw,format=NV12 ! qsvh264enc bitrate=$BITRATE"
            ;;
        vaapi)
            echo "videoconvert ! video/x-raw,format=NV12 ! vaapih264enc bitrate=$BITRATE"
            ;;
        *)
            # Software floor - always available, universally compatible
            echo "videoconvert ! video/x-raw,format=I420 ! x264enc tune=zerolatency bitrate=$BITRATE speed-preset=ultrafast"
            ;;
    esac
}

# Pick the first candidate that is installed AND actually encodes on this box.
detect_encoder() {
    local entry etype elem fmt
    for entry in "${ENCODERS[@]}"; do
        IFS='|' read -r etype elem fmt <<<"$entry"
        gst-inspect-1.0 "$elem" >/dev/null 2>&1 || continue
        echo "  Testing $etype ($elem)..." >&2
        # 5s budget: hardware encoders can take ~2s to cold-init the GPU
        if timeout 5 gst-launch-1.0 videotestsrc num-buffers=10 ! videoconvert ! \
            "video/x-raw,format=$fmt" ! "$elem" ! fakesink >/dev/null 2>&1; then
            echo "  [OK] $etype available" >&2
            echo "$etype"
            return
        fi
        echo "  [--] $etype present but no working hardware" >&2
    done
    echo "  [OK] software (CPU)" >&2
    echo "software"
}

echo "Detecting hardware encoders..."
ENCODER_TYPE=$(detect_encoder)
echo ""
echo "Selected: $ENCODER_TYPE encoder"
echo ""

# Handle different sources
if [ "$SOURCE_CHOICE" -eq 1 ]; then
    # === CAMERA ===
    echo "Available cameras:"
    i=0
    DEVICES=()
    for dev in /dev/video*; do
        if [ -c "$dev" ]; then
            if timeout 1 gst-launch-1.0 v4l2src device="$dev" num-buffers=1 ! fakesink 2>/dev/null; then
                DEVICES+=("$dev")
                echo "  [$i] $dev"
                ((i++))
            fi
        fi
    done

    if [ ${#DEVICES[@]} -eq 0 ]; then
        echo "ERROR: No cameras found"
        exit 1
    fi

    echo ""
    read -rp "Select camera [0]: " CAM_CHOICE
    CAM_CHOICE=${CAM_CHOICE:-0}
    CAMERA="${DEVICES[$CAM_CHOICE]}"

    echo ""
    echo "Probing camera formats..."

    # Try common formats
    for res in "640x480" "640x360" "800x600" "1280x720"; do
        WIDTH=${res%x*}
        HEIGHT=${res#*x}

        if timeout 2 gst-launch-1.0 v4l2src device="$CAMERA" num-buffers=1 ! \
            "video/x-raw,width=$WIDTH,height=$HEIGHT,framerate=30/1" ! fakesink 2>/dev/null; then
            CAM_WIDTH=$WIDTH
            CAM_HEIGHT=$HEIGHT
            echo "Using: ${res} @ 30fps"
            break
        fi
    done

    CAM_WIDTH=${CAM_WIDTH:-640}
    CAM_HEIGHT=${CAM_HEIGHT:-480}

    echo ""
    echo "Streaming camera..."
    echo "Press Ctrl+C to stop"
    echo ""

    # Try hardware encoder first
    ENCODER_PIPELINE=$(encoder_pipeline "$ENCODER_TYPE")

    # shellcheck disable=SC2086
    gst-launch-1.0 -v \
        v4l2src device="$CAMERA" ! \
        "video/x-raw,width=$CAM_WIDTH,height=$CAM_HEIGHT,framerate=30/1" ! \
        $ENCODER_PIPELINE ! \
        h264parse ! \
        rtph264pay config-interval=1 pt=96 ! \
        udpsink host="$DEST_IP" port=$PORT 2>&1 | tee /tmp/stream_error.log &

    STREAM_PID=$!
    sleep 3

    # Check if failed
    if ! kill -0 $STREAM_PID 2>/dev/null; then
        echo ""
        echo "Hardware encoder failed. Switching to software encoder..."
        echo ""

        # Software fallback - guaranteed to work
        ENCODER_PIPELINE=$(encoder_pipeline software)

        # shellcheck disable=SC2086
        gst-launch-1.0 -v \
            v4l2src device="$CAMERA" ! \
            "video/x-raw,width=$CAM_WIDTH,height=$CAM_HEIGHT,framerate=30/1" ! \
            $ENCODER_PIPELINE ! \
            h264parse ! \
            rtph264pay config-interval=1 pt=96 ! \
            udpsink host="$DEST_IP" port=$PORT
    else
        wait $STREAM_PID
    fi

elif [ "$SOURCE_CHOICE" -eq 2 ]; then
    # === VIDEO FILE ===
    read -rp "Enter video file path: " VIDEO_FILE
    if [ ! -f "$VIDEO_FILE" ]; then
        echo "ERROR: File not found"
        exit 1
    fi

    echo ""
    echo "Streaming video file (re-encoding for compatibility)..."
    echo "Press Ctrl+C to stop"
    echo ""

    # decodebin handles any container/codec; then re-encode to compatible H.264
    ENCODER_PIPELINE=$(encoder_pipeline "$ENCODER_TYPE")

    # shellcheck disable=SC2086
    gst-launch-1.0 -v \
        filesrc location="$VIDEO_FILE" ! \
        decodebin ! \
        $ENCODER_PIPELINE ! \
        h264parse ! \
        rtph264pay config-interval=1 pt=96 ! \
        udpsink host="$DEST_IP" port=$PORT

else
    # === TEST PATTERN ===
    echo "Streaming test pattern..."
    echo "Press Ctrl+C to stop"
    echo ""

    # Try hardware encoder first
    ENCODER_PIPELINE=$(encoder_pipeline "$ENCODER_TYPE")

    # shellcheck disable=SC2086
    gst-launch-1.0 -v \
        videotestsrc pattern=smpte is-live=true ! \
        "video/x-raw,width=1280,height=720,framerate=30/1" ! \
        $ENCODER_PIPELINE ! \
        h264parse ! \
        rtph264pay config-interval=1 pt=96 ! \
        udpsink host="$DEST_IP" port=$PORT 2>&1 | tee /tmp/stream_error.log &

    STREAM_PID=$!
    sleep 3

    # Check if failed
    if ! kill -0 $STREAM_PID 2>/dev/null; then
        echo ""
        echo "Hardware encoder failed. Switching to software encoder..."
        echo ""

        # Software fallback - guaranteed to work
        ENCODER_PIPELINE=$(encoder_pipeline software)

        # shellcheck disable=SC2086
        gst-launch-1.0 -v \
            videotestsrc pattern=smpte is-live=true ! \
            "video/x-raw,width=1280,height=720,framerate=30/1" ! \
            $ENCODER_PIPELINE ! \
            h264parse ! \
            rtph264pay config-interval=1 pt=96 ! \
            udpsink host="$DEST_IP" port=$PORT
    else
        wait $STREAM_PID
    fi
fi
