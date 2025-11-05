# Simple Video Streaming

Stream video between laptops or test locally.

## Quick Start

### 1. Install (One Time)

```bash
chmod +x setup.sh
sudo ./setup.sh
```

### 2. Make Scripts Executable

```bash
chmod +x stream.sh view.sh
```

### 3. Test Locally (One Laptop)

**Terminal 1 - Viewer (start first):**
```bash
./view.sh
```

**Terminal 2 - Streamer:**
```bash
./stream.sh
```
When asked for IP, just press **Enter** (uses localhost)  
Choose **[3]** for test pattern (no camera needed)

A video window will pop up with colorful bars.

### 4. Stream Between Laptops

**Laptop A (receiver):**
```bash
./view.sh
```
Note the IP address shown by: `ip addr`

**Laptop B (sender):**
```bash
./stream.sh
```
Enter Laptop A's IP address  
Choose camera [1] or test pattern [3]

## What Each Script Does

### setup.sh
- Installs GStreamer
- Configures firewall
- Checks for hardware encoders

### stream.sh
- Asks for destination IP (empty = localhost)
- Tests connection (for remote IPs)
- Auto-detects best encoder (NVIDIA/VA-API/software)
- Streams camera, video file, or test pattern

### view.sh
- Auto-detects best decoder
- Receives and displays video
- Has automatic fallback if primary pipeline fails

## Supported Encoders

The scripts use **intelligent hardware detection** with priority order:

### Encoder Priority (stream.sh)
1. **NVIDIA** (nvh264enc) - Best for NVIDIA GPUs
2. **QuickSync** (qsvh264enc) - Intel CPUs with iGPU
3. **VA-API** (vaapih264enc) - Intel/AMD integrated graphics
4. **Software** (x264enc) - CPU encoding (always works)

### Decoder Priority (view.sh)
1. **NVIDIA** (nvh264dec) - Best for NVIDIA GPUs
2. **QuickSync** (qsvh264dec) - Intel CPUs with iGPU
3. **VA-API** (vaapih264dec) - Intel/AMD integrated graphics
4. **Software** (avdec_h264) - CPU decoding (always works)

**How Detection Works:**
1. Checks if plugin exists
2. **Tests if hardware actually works** (not just installed)
3. Uses first hardware that passes both checks
4. Falls back to next option if hardware fails

**What You'll See:**
```
Detecting hardware encoders...
  Testing NVIDIA encoder...
  [✗] NVIDIA plugin exists but no hardware
  Testing VA-API encoder...
  [✓] VA-API hardware available

Using: VA-API hardware encoder
```

**Automatic Fallback:** If hardware encoding/decoding fails during streaming, automatically falls back to software.

See **[HARDWARE_DETECTION.md](./HARDWARE_DETECTION.md)** for detailed explanation.

## Troubleshooting

### No video window appears
```bash
# Kill any stuck processes
killall gst-launch-1.0

# Try again: viewer first, then streamer
```

### Cannot reach remote IP
```bash
# On both laptops, check firewall
sudo ufw status

# If active, ensure port 5004 is allowed
sudo ufw allow 5004/udp
```

### Camera not found
```bash
# List cameras
ls -l /dev/video*

# Test camera
gst-launch-1.0 v4l2src device=/dev/video0 ! autovideosink

# Or just use test pattern [3]
```

### Check what's using port 5004
```bash
sudo netstat -tulpn | grep 5004
```

## Technical Details

- **Port:** 5004/UDP
- **Protocol:** RTP/H.264
- **Default resolution:** 640x480 or 1280x720
- **Bitrate:** 3000 kbps
- **Latency buffer:** 50ms

## Examples

### Local test with test pattern
```bash
# Terminal 1
./view.sh

# Terminal 2
./stream.sh
[Press Enter for localhost]
Choice: 3
```

### Remote streaming with camera
```bash
# Laptop A (viewer)
./view.sh

# Laptop B (streamer)
./stream.sh
Enter destination IP: 192.168.1.100
Choice: 1
Select camera: 0
```

### Stream video file
```bash
./stream.sh
Enter destination IP: [target IP or Enter]
Choice: 2
Enter video file path: /path/to/video.mp4
```

## Notes

- Always start the **viewer first**, then the streamer
- For localhost testing, no network connection needed
- For remote streaming, both laptops must be on same network
- Test pattern always works (no camera required)
- Software encoding works on any system (no GPU required)
