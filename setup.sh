#!/bin/bash
# Setup Script for Video Streaming
# Installs GStreamer and configures firewall

echo "=== Video Streaming Setup ==="
echo ""

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo:"
    echo "  sudo bash setup.sh"
    exit 1
fi

# Check OS
if [ ! -f /etc/os-release ]; then
    echo "ERROR: Cannot detect OS"
    exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release

# Accept Debian/Ubuntu and their derivatives (Raspberry Pi OS, Jetson L4T, ...).
case " $ID ${ID_LIKE:-} " in
    *" ubuntu "* | *" debian "* | *" raspbian "*) ;;
    *)
        echo "ERROR: apt-based Debian/Ubuntu systems only (incl. Raspberry Pi OS, Jetson L4T)."
        echo "On Yocto/BSP boards (i.MX, Qualcomm) install GStreamer via your BSP instead."
        exit 1
        ;;
esac

echo "Detected: $PRETTY_NAME"
echo ""

# Update package list
echo "Step 1: Updating package list..."
apt-get update -qq

echo ""
echo "Step 2: Installing GStreamer..."
echo ""

# Core packages (present on x86 and ARM). plugins-good/bad carry the V4L2 codec
# elements used by Raspberry Pi, i.MX, Qualcomm and Rockchip boards.
apt-get install -y \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-x \
    v4l-utils

# VA-API (Intel/AMD) is best-effort - it is not present on ARM boards.
apt-get install -y gstreamer1.0-vaapi || echo "  (skipped gstreamer1.0-vaapi - not available here)"

echo ""
echo "Step 3: Checking firewall..."
echo ""

# Configure firewall if present
if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "Status: active"; then
        echo "UFW is active. Adding rule for port 5004/udp..."
        ufw allow 5004/udp
        echo "Firewall rule added"
    else
        echo "UFW is installed but not active"
        echo "No firewall configuration needed"
    fi
else
    echo "UFW not installed"
    echo "No firewall configuration needed"
fi

echo ""
echo "Step 4: Verifying installation..."
echo ""

# Verify GStreamer
if gst-launch-1.0 --version >/dev/null 2>&1; then
    echo "GStreamer: OK"
    gst-launch-1.0 --version | head -n 1
else
    echo "ERROR: GStreamer installation failed"
    exit 1
fi

# Check encoders
echo ""
echo "Available encoders:"
gst-inspect-1.0 nvh264enc >/dev/null 2>&1 && echo "  - NVIDIA desktop (NVENC)"
gst-inspect-1.0 nvv4l2h264enc >/dev/null 2>&1 && echo "  - NVIDIA Jetson (nvv4l2)"
gst-inspect-1.0 vah264enc >/dev/null 2>&1 && echo "  - VA (modern VA-API)"
gst-inspect-1.0 qsvh264enc >/dev/null 2>&1 && echo "  - QuickSync"
gst-inspect-1.0 vaapih264enc >/dev/null 2>&1 && echo "  - VA-API (legacy)"
gst-inspect-1.0 v4l2h264enc >/dev/null 2>&1 && echo "  - V4L2 (Pi/i.MX/Qualcomm/Rockchip)"
echo "  - x264 software (always available)"

# Check cameras
echo ""
echo "Cameras detected:"
if ls /dev/video* >/dev/null 2>&1; then
    ls /dev/video*
else
    echo "  None (you can still use test pattern)"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Local testing (one machine):"
echo "     Terminal 1: ./view.sh"
echo "     Terminal 2: ./stream.sh (press Enter for localhost)"
echo ""
echo "  2. Remote streaming (two machines):"
echo "     Receiver: ./view.sh"
echo "     Sender:   ./stream.sh (enter the receiver's IP)"
echo ""
