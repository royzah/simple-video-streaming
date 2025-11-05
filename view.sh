#!/bin/bash
# Simple Video Viewer with Robust Hardware Detection
# Receives and displays video stream

PORT=5004
LATENCY=50

echo "=== Video Viewer ==="
echo ""

# Comprehensive decoder detection with priority order
echo "Detecting hardware decoders..."
DECODER_TYPE=""

# Priority 1: NVIDIA (best performance on NVIDIA GPUs)
if gst-inspect-1.0 nvh264dec > /dev/null 2>&1; then
    echo "  Testing NVIDIA decoder..."
    if timeout 2 gst-launch-1.0 videotestsrc num-buffers=1 ! video/x-raw,format=I420 ! nvh264enc ! h264parse ! nvh264dec ! fakesink 2>/dev/null; then
        DECODER_TYPE="nvidia"
        echo "  [✓] NVIDIA hardware available"
    else
        echo "  [✗] NVIDIA plugin exists but no hardware"
    fi
fi

# Priority 2: Intel QuickSync (good for Intel GPUs)
if [ -z "$DECODER_TYPE" ] && gst-inspect-1.0 qsvh264dec > /dev/null 2>&1; then
    echo "  Testing QuickSync decoder..."
    if timeout 2 gst-launch-1.0 videotestsrc num-buffers=1 ! video/x-raw,format=NV12 ! vaapih264enc ! h264parse ! qsvh264dec ! fakesink 2>/dev/null; then
        DECODER_TYPE="quicksync"
        echo "  [✓] QuickSync hardware available"
    else
        echo "  [✗] QuickSync plugin exists but no hardware"
    fi
fi

# Priority 3: VA-API (works on Intel/AMD integrated graphics)
if [ -z "$DECODER_TYPE" ] && gst-inspect-1.0 vaapih264dec > /dev/null 2>&1; then
    echo "  Testing VA-API decoder..."
    if timeout 2 gst-launch-1.0 videotestsrc num-buffers=1 ! video/x-raw,format=NV12 ! vaapih264enc ! h264parse ! vaapih264dec ! fakesink 2>/dev/null; then
        DECODER_TYPE="vaapi"
        echo "  [✓] VA-API hardware available"
    else
        echo "  [✗] VA-API plugin exists but no hardware"
    fi
fi

# Priority 4: Software fallback (always works, handles all H.264 profiles)
if [ -z "$DECODER_TYPE" ]; then
    DECODER_TYPE="software"
    echo "  [✓] Software decoder (CPU)"
fi

echo ""
case "$DECODER_TYPE" in
    nvidia)
        DECODER="nvh264dec"
        echo "Using: NVIDIA hardware decoder"
        ;;
    quicksync)
        DECODER="qsvh264dec"
        echo "Using: Intel QuickSync hardware decoder"
        ;;
    vaapi)
        DECODER="vaapih264dec"
        echo "Using: VA-API hardware decoder"
        ;;
    software)
        DECODER="avdec_h264"
        echo "Using: Software decoder (CPU)"
        ;;
esac

echo ""
echo "Listening on port: $PORT"
echo "Latency: ${LATENCY}ms"
echo ""
echo "Waiting for stream..."
echo "Press Ctrl+C to stop"
echo ""

# Try primary pipeline with detected decoder
gst-launch-1.0 -v \
    udpsrc port=$PORT caps="application/x-rtp,media=video,clock-rate=90000,encoding-name=H264,payload=96" ! \
    rtpjitterbuffer latency=$LATENCY drop-on-latency=true ! \
    rtph264depay ! \
    h264parse ! \
    $DECODER ! \
    videoconvert ! \
    autovideosink sync=false 2>&1 | tee /tmp/viewer_error.log &

VIEWER_PID=$!

# Monitor pipeline
sleep 3
if ! kill -0 $VIEWER_PID 2>/dev/null; then
    # Check if it was a negotiation failure
    if grep -q "not-negotiated" /tmp/viewer_error.log 2>/dev/null; then
        echo ""
        echo "Hardware decoder failed (profile incompatibility)."
        echo "Trying software decoder..."
        echo ""
        echo "Note: Software decoder handles all H.264 profiles"
        echo ""
        
        # Fallback: software decoder (handles ALL H.264 profiles)
        gst-launch-1.0 -v \
            udpsrc port=$PORT caps="application/x-rtp,media=video,clock-rate=90000,encoding-name=H264,payload=96" ! \
            rtpjitterbuffer latency=$LATENCY drop-on-latency=true ! \
            rtph264depay ! \
            h264parse ! \
            avdec_h264 ! \
            videoconvert ! \
            autovideosink sync=false
    else
        echo ""
        echo "Primary decoder failed. Trying fallback..."
        echo ""
        
        # Generic fallback
        gst-launch-1.0 -v \
            udpsrc port=$PORT ! \
            "application/x-rtp" ! \
            rtpjitterbuffer latency=$LATENCY ! \
            rtph264depay ! \
            h264parse ! \
            avdec_h264 ! \
            videoconvert ! \
            autovideosink
    fi
else
    echo "Video window should appear"
    echo ""
    
    # Wait for pipeline
    wait $VIEWER_PID
fi
