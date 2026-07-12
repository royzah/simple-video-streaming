#!/bin/bash
# Video Viewer - receives H.264 over RTP/UDP and displays it.
# decodebin auto-selects the best available decoder (NVIDIA/VA/VA-API/software)
# and falls back automatically, so no manual detection is needed.

PORT=${PORT:-5004}
LATENCY=${LATENCY:-50}

echo "=== Video Viewer ==="
echo ""
echo "Listening on port: $PORT"
echo "Latency: ${LATENCY}ms"
echo "Decoder: auto (decodebin picks hardware, falls back to software)"
echo ""
echo "Waiting for stream..."
echo "Press Ctrl+C to stop"
echo ""

gst-launch-1.0 -v \
    udpsrc port="$PORT" caps="application/x-rtp,media=video,clock-rate=90000,encoding-name=H264,payload=96" ! \
    rtpjitterbuffer latency="$LATENCY" drop-on-latency=true ! \
    rtph264depay ! \
    h264parse ! \
    decodebin ! \
    videoconvert ! \
    autovideosink sync=false
