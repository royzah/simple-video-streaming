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

. /etc/os-release

if [ "$ID" != "ubuntu" ] && [ "$ID" != "debian" ]; then
    echo "ERROR: This script is for Ubuntu/Debian only"
    exit 1
fi

echo "Detected: $PRETTY_NAME"
echo ""

# Update package list
echo "Step 1: Updating package list..."
apt-get update -qq

echo ""
echo "Step 2: Installing GStreamer..."
echo ""

# Install GStreamer packages
apt-get install -y \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-x \
    gstreamer1.0-vaapi \
    v4l-utils

echo ""
echo "Step 3: Checking firewall..."
echo ""

# Configure firewall if present
if command -v ufw > /dev/null 2>&1; then
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
if gst-launch-1.0 --version > /dev/null 2>&1; then
    echo "GStreamer: OK"
    gst-launch-1.0 --version | head -n 1
else
    echo "ERROR: GStreamer installation failed"
    exit 1
fi

# Check encoders
echo ""
echo "Available encoders:"
if gst-inspect-1.0 nvh264enc > /dev/null 2>&1; then
    echo "  - NVIDIA hardware"
fi
if gst-inspect-1.0 vaapih264enc > /dev/null 2>&1; then
    echo "  - VA-API hardware"
fi
echo "  - x264 software (always available)"

# Check cameras
echo ""
echo "Cameras detected:"
if ls /dev/video* > /dev/null 2>&1; then
    ls /dev/video*
else
    echo "  None (you can still use test pattern)"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Make scripts executable:"
echo "     chmod +x stream.sh view.sh"
echo ""
echo "  2. For local testing (one laptop):"
echo "     Terminal 1: ./view.sh"
echo "     Terminal 2: ./stream.sh (press Enter for localhost)"
echo ""
echo "  3. For remote streaming (two laptops):"
echo "     Laptop A: ./view.sh"
echo "     Laptop B: ./stream.sh (enter Laptop A's IP)"
echo ""
