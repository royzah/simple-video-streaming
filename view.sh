#!/bin/bash
# Video Viewer - receives H.264/H.265 over RTP/UDP and displays it.
# decodebin auto-selects the best available decoder (NVIDIA/VA/VA-API, Jetson
# nvv4l2decoder, ARM v4l2 decoders) and falls back to software on its own.
# CODEC=h264 (default) or CODEC=h265 - must match the streamer's CODEC.

PORT=${PORT:-5004}
LATENCY=${LATENCY:-50}
CODEC=${CODEC:-h264}

case "$CODEC" in
    h264) HNUM=264 ;;
    h265) HNUM=265 ;;
    *)
        echo "ERROR: CODEC must be h264 or h265 (got '$CODEC')"
        exit 1
        ;;
esac

DEPAY="rtph${HNUM}depay"
PARSE="h${HNUM}parse"
CAPS="application/x-rtp,media=video,clock-rate=90000,encoding-name=H${HNUM},payload=96"

# Jetson decoders output NVMM buffers; nvvidconv bridges them to system memory.
# On any other platform videoconvert alone is used.
if gst-inspect-1.0 nvvidconv >/dev/null 2>&1; then
    CONVERT="nvvidconv ! videoconvert"
else
    CONVERT="videoconvert"
fi

echo "=== Video Viewer ==="
echo "Codec: $CODEC"
echo "Listening on port: $PORT"
echo "Latency: ${LATENCY}ms"
echo "Decoder: auto (decodebin picks hardware, falls back to software)"
echo ""
echo "Waiting for stream..."
echo "Press Ctrl+C to stop"
echo ""

# shellcheck disable=SC2086
gst-launch-1.0 -v \
    udpsrc port="$PORT" caps="$CAPS" ! \
    rtpjitterbuffer latency="$LATENCY" drop-on-latency=true ! \
    "$DEPAY" ! \
    "$PARSE" ! \
    decodebin ! \
    $CONVERT ! \
    autovideosink sync=false
