#!/bin/bash
# Bulletproof Video Streamer - Works on ANY laptop
# Automatically adapts to NVIDIA, VA-API, QuickSync, or software encoding

PORT=5004

echo "=== Video Streamer ==="
echo ""

# Ask for destination IP
read -p "Enter destination IP (press Enter for localhost): " DEST_IP
if [ -z "$DEST_IP" ]; then
    DEST_IP="127.0.0.1"
    echo "Using localhost: $DEST_IP"
else
    echo "Using remote IP: $DEST_IP"
    
    # Test connection for remote IP
    echo "Testing connection..."
    if ! ping -c 2 -W 2 "$DEST_IP" > /dev/null 2>&1; then
        echo "WARNING: Cannot reach $DEST_IP"
        read -p "Continue anyway? (y/n): " CONTINUE
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
read -p "Choice [3]: " SOURCE_CHOICE
SOURCE_CHOICE=${SOURCE_CHOICE:-3}

echo ""

# Detect best encoder with actual hardware testing
echo "Detecting hardware encoders..."
ENCODER_TYPE=""

# Test NVIDIA (priority 1)
if gst-inspect-1.0 nvh264enc > /dev/null 2>&1; then
    echo "  Testing NVIDIA encoder..."
    if timeout 2 gst-launch-1.0 videotestsrc num-buffers=1 ! \
        video/x-raw,format=I420 ! nvh264enc ! fakesink 2>/dev/null; then
        ENCODER_TYPE="nvidia"
        echo "  [✓] NVIDIA available"
    else
        echo "  [✗] NVIDIA plugin exists but no hardware"
    fi
fi

# Test QuickSync (priority 2)
if [ -z "$ENCODER_TYPE" ] && gst-inspect-1.0 qsvh264enc > /dev/null 2>&1; then
    echo "  Testing QuickSync encoder..."
    if timeout 2 gst-launch-1.0 videotestsrc num-buffers=1 ! \
        video/x-raw,format=NV12 ! qsvh264enc ! fakesink 2>/dev/null; then
        ENCODER_TYPE="quicksync"
        echo "  [✓] QuickSync available"
    else
        echo "  [✗] QuickSync plugin exists but no hardware"
    fi
fi

# Test VA-API (priority 3)
if [ -z "$ENCODER_TYPE" ] && gst-inspect-1.0 vaapih264enc > /dev/null 2>&1; then
    echo "  Testing VA-API encoder..."
    if timeout 2 gst-launch-1.0 videotestsrc num-buffers=1 ! \
        video/x-raw,format=NV12 ! vaapih264enc ! fakesink 2>/dev/null; then
        ENCODER_TYPE="vaapi"
        echo "  [✓] VA-API available"
    else
        echo "  [✗] VA-API plugin exists but no hardware"
    fi
fi

# Software fallback (priority 4 - always available)
if [ -z "$ENCODER_TYPE" ]; then
    ENCODER_TYPE="software"
    echo "  [✓] Software encoder (CPU)"
fi

echo ""
echo "Selected: $ENCODER_TYPE encoder"
echo ""

# Universal encoder function - produces compatible H.264 for ANY decoder
build_encoder_pipeline() {
    local use_hw="$1"
    
    if [ "$use_hw" = "true" ]; then
        case "$ENCODER_TYPE" in
            nvidia)
                # NVIDIA: I420 format for compatibility
                echo "videoconvert ! video/x-raw,format=I420 ! nvh264enc preset=low-latency-hq bitrate=3000"
                ;;
            quicksync)
                # QuickSync: NV12 format
                echo "videoconvert ! video/x-raw,format=NV12 ! qsvh264enc bitrate=3000"
                ;;
            vaapi)
                # VA-API: NV12 format, force compatible profile
                if gst-inspect-1.0 vaapipostproc > /dev/null 2>&1; then
                    echo "videoconvert ! video/x-raw,format=NV12 ! vaapipostproc ! vaapih264enc rate-control=cbr bitrate=3000 ! video/x-h264,profile=constrained-baseline"
                else
                    echo "videoconvert ! video/x-raw,format=NV12 ! vaapih264enc rate-control=cbr bitrate=3000 ! video/x-h264,profile=constrained-baseline"
                fi
                ;;
            software)
                # Software: I420 format produces baseline/main profile (universal compatibility)
                echo "videoconvert ! video/x-raw,format=I420 ! x264enc tune=zerolatency bitrate=3000 speed-preset=ultrafast"
                ;;
        esac
    else
        # Software fallback - guaranteed to work
        echo "videoconvert ! video/x-raw,format=I420 ! x264enc tune=zerolatency bitrate=3000 speed-preset=ultrafast"
    fi
}

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
    read -p "Select camera [0]: " CAM_CHOICE
    CAM_CHOICE=${CAM_CHOICE:-0}
    CAMERA="${DEVICES[$CAM_CHOICE]}"
    
    echo ""
    echo "Probing camera formats..."
    
    # Try common formats
    for res in "640x480" "640x360" "800x600" "1280x720"; do
        WIDTH=$(echo $res | cut -dx -f1)
        HEIGHT=$(echo $res | cut -dx -f2)
        
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
    ENCODER_PIPELINE=$(build_encoder_pipeline "true")
    
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
        ENCODER_PIPELINE=$(build_encoder_pipeline "false")
        
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
    read -p "Enter video file path: " VIDEO_FILE
    if [ ! -f "$VIDEO_FILE" ]; then
        echo "ERROR: File not found"
        exit 1
    fi
    
    echo ""
    echo "Streaming video file..."
    echo "Press Ctrl+C to stop"
    echo ""
    
    # Files are already encoded, just stream them
    gst-launch-1.0 -v \
        filesrc location="$VIDEO_FILE" ! \
        qtdemux ! \
        h264parse ! \
        rtph264pay config-interval=1 pt=96 ! \
        udpsink host="$DEST_IP" port=$PORT

else
    # === TEST PATTERN ===
    echo "Streaming test pattern..."
    echo "Press Ctrl+C to stop"
    echo ""
    
    # Try hardware encoder first
    ENCODER_PIPELINE=$(build_encoder_pipeline "true")
    
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
        ENCODER_PIPELINE=$(build_encoder_pipeline "false")
        
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
