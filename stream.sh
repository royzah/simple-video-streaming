#!/bin/bash
# Simple Video Streamer
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

# Detect best encoder
echo "Detecting encoder..."
if gst-inspect-1.0 nvh264enc > /dev/null 2>&1; then
    ENCODER_TYPE="nvidia"
    echo "Using: NVIDIA hardware encoder"
elif gst-inspect-1.0 vaapih264enc > /dev/null 2>&1; then
    ENCODER_TYPE="vaapi"
    echo "Using: VA-API hardware encoder"
else
    ENCODER_TYPE="software"
    echo "Using: x264 software encoder"
fi

echo ""

# Function to build encoder pipeline
build_encoder_pipeline() {
    if [ "$ENCODER_TYPE" = "nvidia" ]; then
        echo "videoconvert ! video/x-raw,format=I420 ! nvh264enc preset=low-latency-hq bitrate=3000"
    elif [ "$ENCODER_TYPE" = "vaapi" ]; then
        if gst-inspect-1.0 vaapipostproc > /dev/null 2>&1; then
            echo "vaapipostproc ! vaapih264enc rate-control=cbr bitrate=3000"
        else
            echo "videoconvert ! vaapih264enc rate-control=cbr bitrate=3000"
        fi
    else
        echo "videoconvert ! x264enc tune=zerolatency bitrate=3000 speed-preset=ultrafast"
    fi
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
    
    gst-launch-1.0 -v \
        v4l2src device="$CAMERA" ! \
        "video/x-raw,width=$CAM_WIDTH,height=$CAM_HEIGHT,framerate=30/1" ! \
        $ENCODER_PIPELINE ! \
        h264parse ! \
        rtph264pay config-interval=1 pt=96 ! \
        udpsink host="$DEST_IP" port=$PORT

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
    
    gst-launch-1.0 -v \
        videotestsrc pattern=smpte is-live=true ! \
        "video/x-raw,width=1280,height=720,framerate=30/1" ! \
        $ENCODER_PIPELINE ! \
        h264parse ! \
        rtph264pay config-interval=1 pt=96 ! \
        udpsink host="$DEST_IP" port=$PORT
fi
