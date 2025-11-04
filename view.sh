#!/bin/bash
# Simple Video Viewer
# Receives and displays video stream

PORT=5004
LATENCY=50

echo "=== Video Viewer ==="
echo ""

# Detect best decoder
echo "Detecting decoder..."
if gst-inspect-1.0 nvh264dec > /dev/null 2>&1; then
    DECODER="nvh264dec"
    echo "Using: NVIDIA hardware decoder"
elif gst-inspect-1.0 vaapih264dec > /dev/null 2>&1; then
    DECODER="vaapih264dec"
    echo "Using: VA-API hardware decoder"
else
    DECODER="avdec_h264"
    echo "Using: Software decoder"
fi

echo ""
echo "Listening on port: $PORT"
echo "Latency: ${LATENCY}ms"
echo ""
echo "Waiting for stream..."
echo "Press Ctrl+C to stop"
echo ""

# Try primary pipeline
gst-launch-1.0 -v \
    udpsrc port=$PORT caps="application/x-rtp,media=video,clock-rate=90000,encoding-name=H264,payload=96" ! \
    rtpjitterbuffer latency=$LATENCY drop-on-latency=true ! \
    rtph264depay ! \
    h264parse ! \
    $DECODER ! \
    videoconvert ! \
    autovideosink sync=false 2>&1 &

VIEWER_PID=$!

# Monitor pipeline
sleep 3
if ! kill -0 $VIEWER_PID 2>/dev/null; then
    echo ""
    echo "Primary pipeline failed. Trying fallback..."
    echo ""
    
    # Fallback: simpler pipeline
    gst-launch-1.0 -v \
        udpsrc port=$PORT ! \
        "application/x-rtp" ! \
        rtpjitterbuffer latency=$LATENCY ! \
        rtph264depay ! \
        h264parse ! \
        avdec_h264 ! \
        videoconvert ! \
        autovideosink
else
    echo "Video window should appear"
    echo ""
    
    # Wait for pipeline
    wait $VIEWER_PID
fi
