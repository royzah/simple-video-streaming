#!/bin/bash
# Bulletproof Video Viewer - Works with ANY encoder
# Automatically adapts to NVIDIA, VA-API, QuickSync, or software decoding

PORT=5004
LATENCY=50

echo "=== Video Viewer ==="
echo ""

# Detect best decoder with actual hardware testing
echo "Detecting hardware decoders..."
DECODER_TYPE=""

# Test NVIDIA (priority 1)
if gst-inspect-1.0 nvh264dec > /dev/null 2>&1; then
    echo "  Testing NVIDIA decoder..."
    if timeout 2 gst-launch-1.0 videotestsrc num-buffers=1 ! \
        video/x-raw,format=I420 ! nvh264enc ! h264parse ! nvh264dec ! fakesink 2>/dev/null; then
        DECODER_TYPE="nvidia"
        echo "  [✓] NVIDIA available"
    else
        echo "  [✗] NVIDIA plugin exists but no hardware"
    fi
fi

# Test QuickSync (priority 2)
if [ -z "$DECODER_TYPE" ] && gst-inspect-1.0 qsvh264dec > /dev/null 2>&1; then
    echo "  Testing QuickSync decoder..."
    if timeout 2 gst-launch-1.0 videotestsrc num-buffers=1 ! \
        video/x-raw,format=NV12 ! vaapih264enc ! h264parse ! qsvh264dec ! fakesink 2>/dev/null; then
        DECODER_TYPE="quicksync"
        echo "  [✓] QuickSync available"
    else
        echo "  [✗] QuickSync plugin exists but no hardware"
    fi
fi

# Test VA-API (priority 3)
if [ -z "$DECODER_TYPE" ] && gst-inspect-1.0 vaapih264dec > /dev/null 2>&1; then
    echo "  Testing VA-API decoder..."
    if timeout 2 gst-launch-1.0 videotestsrc num-buffers=1 ! \
        video/x-raw,format=NV12 ! vaapih264enc ! h264parse ! vaapih264dec ! fakesink 2>/dev/null; then
        DECODER_TYPE="vaapi"
        echo "  [✓] VA-API available"
    else
        echo "  [✗] VA-API plugin exists but no hardware"
    fi
fi

# Software fallback (priority 4 - always available, handles ALL profiles)
if [ -z "$DECODER_TYPE" ]; then
    DECODER_TYPE="software"
    echo "  [✓] Software decoder (CPU)"
fi

echo ""
case "$DECODER_TYPE" in
    nvidia)
        DECODER="nvh264dec"
        echo "Selected: NVIDIA decoder"
        ;;
    quicksync)
        DECODER="qsvh264dec"
        echo "Selected: QuickSync decoder"
        ;;
    vaapi)
        DECODER="vaapih264dec"
        echo "Selected: VA-API decoder"
        ;;
    software)
        DECODER="avdec_h264"
        echo "Selected: Software decoder (CPU)"
        ;;
esac

echo ""
echo "Listening on port: $PORT"
echo "Latency: ${LATENCY}ms"
echo ""
echo "Waiting for stream..."
echo "Press Ctrl+C to stop"
echo ""

# Try hardware decoder first
gst-launch-1.0 -v \
    udpsrc port=$PORT caps="application/x-rtp,media=video,clock-rate=90000,encoding-name=H264,payload=96" ! \
    rtpjitterbuffer latency=$LATENCY drop-on-latency=true ! \
    rtph264depay ! \
    h264parse ! \
    $DECODER ! \
    videoconvert ! \
    autovideosink sync=false 2>&1 | tee /tmp/viewer_error.log &

VIEWER_PID=$!

# Monitor for failures
sleep 4

if ! kill -0 $VIEWER_PID 2>/dev/null; then
    # Hardware decoder failed - use software fallback
    echo ""
    echo "Hardware decoder failed."
    
    # Check specific error
    if grep -q "not-negotiated" /tmp/viewer_error.log 2>/dev/null; then
        echo "Reason: Profile incompatibility (high-4:4:4 or other advanced profile)"
    elif grep -q "no element" /tmp/viewer_error.log 2>/dev/null; then
        echo "Reason: Missing decoder plugin"
    else
        echo "Reason: Unknown - check /tmp/viewer_error.log"
    fi
    
    echo ""
    echo "Switching to software decoder..."
    echo "Note: Software decoder handles ALL H.264 profiles"
    echo ""
    
    # Software decoder fallback - handles ALL profiles including high-4:4:4
    gst-launch-1.0 -v \
        udpsrc port=$PORT caps="application/x-rtp,media=video,clock-rate=90000,encoding-name=H264,payload=96" ! \
        rtpjitterbuffer latency=$LATENCY drop-on-latency=true ! \
        rtph264depay ! \
        h264parse ! \
        avdec_h264 ! \
        videoconvert ! \
        autovideosink sync=false 2>&1 &
    
    VIEWER_PID=$!
    sleep 2
    
    if ! kill -0 $VIEWER_PID 2>/dev/null; then
        # Even software decoder failed - try ultra-simple pipeline
        echo ""
        echo "Standard pipeline failed. Trying minimal pipeline..."
        echo ""
        
        gst-launch-1.0 -v \
            udpsrc port=$PORT ! \
            application/x-rtp ! \
            rtpjitterbuffer ! \
            rtph264depay ! \
            h264parse ! \
            avdec_h264 ! \
            videoconvert ! \
            autovideosink 2>&1 &
        
        VIEWER_PID=$!
        sleep 2
        
        if ! kill -0 $VIEWER_PID 2>/dev/null; then
            echo ""
            echo "ERROR: All decoder attempts failed"
            echo ""
            echo "Troubleshooting:"
            echo "  1. Make sure streamer is running"
            echo "  2. Check: sudo netstat -tulpn | grep $PORT"
            echo "  3. Check logs: cat /tmp/viewer_error.log"
            echo "  4. Kill stuck processes: killall gst-launch-1.0"
            echo ""
            exit 1
        fi
    fi
    
    echo "Video window should appear"
    wait $VIEWER_PID
else
    echo "Video window should appear"
    echo ""
    wait $VIEWER_PID
fi
