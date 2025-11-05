#!/bin/bash
# Simple Video Streamer with Robust Hardware Detection
# Streams video to localhost or remote IP

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

# Comprehensive encoder detection with priority order
echo "Detecting hardware encoders..."
ENCODER_TYPE=""

# Priority 1: NVIDIA (best performance on NVIDIA GPUs)
if gst-inspect-1.0 nvh264enc > /dev/null 2>&1; then
    echo "  Testing NVIDIA encoder..."
    if timeout 2 gst-launch-1.0 videotestsrc num-buffers=1 ! video/x-raw,format=I420 ! nvh264enc ! fakesink 2>/dev/null; then
        ENCODER_TYPE="nvidia"
        echo "  [✓] NVIDIA hardware available"
    else
        echo "  [✗] NVIDIA plugin exists but no hardware"
    fi
fi

# Priority 2: Intel QuickSync (good for Intel GPUs)
if [ -z "$ENCODER_TYPE" ] && gst-inspect-1.0 qsvh264enc > /dev/null 2>&1; then
    echo "  Testing QuickSync encoder..."
    if timeout 2 gst-launch-1.0 videotestsrc num-buffers=1 ! video/x-raw,format=NV12 ! qsvh264enc ! fakesink 2>/dev/null; then
        ENCODER_TYPE="quicksync"
        echo "  [✓] QuickSync hardware available"
    else
        echo "  [✗] QuickSync plugin exists but no hardware"
    fi
fi

# Priority 3: VA-API (works on Intel/AMD integrated graphics)
if [ -z "$ENCODER_TYPE" ] && gst-inspect-1.0 vaapih264enc > /dev/null 2>&1; then
    echo "  Testing VA-API encoder..."
    if timeout 2 gst-launch-1.0 videotestsrc num-buffers=1 ! video/x-raw,format=NV12 ! vaapih264enc ! fakesink 2>/dev/null; then
        ENCODER_TYPE="vaapi"
        echo "  [✓] VA-API hardware available"
    else
        echo "  [✗] VA-API plugin exists but no hardware"
    fi
fi

# Priority 4: Software fallback (always works)
if [ -z "$ENCODER_TYPE" ]; then
    ENCODER_TYPE="software"
    echo "  [✓] Software encoder (CPU)"
fi

echo ""
case "$ENCODER_TYPE" in
    nvidia)
        echo "Using: NVIDIA hardware encoder"
        ;;
    quicksync)
        echo "Using: Intel QuickSync hardware encoder"
        ;;
    vaapi)
        echo "Using: VA-API hardware encoder"
        ;;
    software)
        echo "Using: x264 software encoder (CPU)"
        ;;
esac

echo ""

# Function to build encoder pipeline based on detected hardware
build_encoder_pipeline() {
    case "$ENCODER_TYPE" in
        nvidia)
            echo "videoconvert ! video/x-raw,format=I420 ! nvh264enc preset=low-latency-hq bitrate=3000"
            ;;
        quicksync)
            echo "videoconvert ! video/x-raw,format=NV12 ! qsvh264enc bitrate=3000"
            ;;
        vaapi)
            # Force constrained-baseline profile for maximum compatibility across decoders
            if gst-inspect-1.0 vaapipostproc > /dev/null 2>&1; then
                echo "videoconvert ! video/x-raw,format=NV12 ! vaapipostproc ! vaapih264enc rate-control=cbr bitrate=3000 ! video/x-h264,profile=constrained-baseline"
            else
                echo "videoconvert ! video/x-raw,format=NV12 ! vaapih264enc rate-control=cbr bitrate=3000 ! video/x-h264,profile=constrained-baseline"
            fi
            ;;
        software)
            # Force I420 format for baseline/main profile compatibility
            echo "videoconvert ! video/x-raw,format=I420 ! x264enc tune=zerolatency bitrate=3000 speed-preset=ultrafast"
            ;;
    esac
}

ENCODER_PIPELINE=$(build_encoder_pipeline)

# Handle different sources
if [ "$SOURCE_CHOICE" -eq 1 ]; then
    # Camera
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
            echo "Using format: ${res} @ 30fps"
            break
        fi
    done
    
    # Fallback
    CAM_WIDTH=${CAM_WIDTH:-640}
    CAM_HEIGHT=${CAM_HEIGHT:-480}
    
    echo ""
    echo "Streaming camera..."
    echo "Press Ctrl+C to stop"
    echo ""
    
    # Try with detected encoder
    gst-launch-1.0 -v \
        v4l2src device="$CAMERA" ! \
        "video/x-raw,width=$CAM_WIDTH,height=$CAM_HEIGHT,framerate=30/1" ! \
        $ENCODER_PIPELINE ! \
        h264parse ! \
        rtph264pay config-interval=1 pt=96 ! \
        udpsink host="$DEST_IP" port=$PORT 2>&1 | tee /tmp/stream_error.log &
    
    STREAM_PID=$!
    
    # Monitor for failures
    sleep 3
    if ! kill -0 $STREAM_PID 2>/dev/null; then
        echo ""
        echo "Hardware encoder failed. Trying software encoder..."
        echo ""
        
        # Fallback to software encoder with I420 format
        gst-launch-1.0 -v \
            v4l2src device="$CAMERA" ! \
            "video/x-raw,width=$CAM_WIDTH,height=$CAM_HEIGHT,framerate=30/1" ! \
            videoconvert ! \
            "video/x-raw,format=I420" ! \
            x264enc tune=zerolatency bitrate=3000 speed-preset=ultrafast ! \
            h264parse ! \
            rtph264pay config-interval=1 pt=96 ! \
            udpsink host="$DEST_IP" port=$PORT
    else
        # Pipeline is running, wait for it
        wait $STREAM_PID
    fi

elif [ "$SOURCE_CHOICE" -eq 2 ]; then
    # Video file
    read -p "Enter video file path: " VIDEO_FILE
    if [ ! -f "$VIDEO_FILE" ]; then
        echo "ERROR: File not found"
        exit 1
    fi
    
    echo ""
    echo "Streaming video file..."
    echo "Press Ctrl+C to stop"
    echo ""
    
    gst-launch-1.0 -v \
        filesrc location="$VIDEO_FILE" ! \
        qtdemux ! \
        h264parse ! \
        rtph264pay config-interval=1 pt=96 ! \
        udpsink host="$DEST_IP" port=$PORT

else
    # Test pattern
    echo "Streaming test pattern..."
    echo "Press Ctrl+C to stop"
    echo ""
    
    # Try with detected encoder
    gst-launch-1.0 -v \
        videotestsrc pattern=smpte is-live=true ! \
        "video/x-raw,width=1280,height=720,framerate=30/1" ! \
        $ENCODER_PIPELINE ! \
        h264parse ! \
        rtph264pay config-interval=1 pt=96 ! \
        udpsink host="$DEST_IP" port=$PORT 2>&1 | tee /tmp/stream_error.log &
    
    STREAM_PID=$!
    
    # Monitor for failures
    sleep 3
    if ! kill -0 $STREAM_PID 2>/dev/null; then
        echo ""
        echo "Hardware encoder failed. Trying software encoder..."
        echo ""
        
        # Fallback to software encoder with I420 format
        gst-launch-1.0 -v \
            videotestsrc pattern=smpte is-live=true ! \
            "video/x-raw,width=1280,height=720,framerate=30/1" ! \
            videoconvert ! \
            "video/x-raw,format=I420" ! \
            x264enc tune=zerolatency bitrate=3000 speed-preset=ultrafast ! \
            h264parse ! \
            rtph264pay config-interval=1 pt=96 ! \
            udpsink host="$DEST_IP" port=$PORT
    else
        # Pipeline is running, wait for it
        wait $STREAM_PID
    fi
fi
