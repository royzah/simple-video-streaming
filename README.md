# Video Streaming

Low-latency H.264 video streaming over UDP/RTP using GStreamer. Works on
NVIDIA, Intel, AMD, or CPU-only machines, with automatic hardware detection and
software fallback.

## Files

- `setup.sh` - install GStreamer and configure the firewall (run once)
- `stream.sh` - send video
- `view.sh` - receive video

## Install

```bash
chmod +x setup.sh
sudo ./setup.sh
```

## Local test (one machine, two terminals)

```bash
# Terminal 1
chmod +x view.sh
./view.sh

# Terminal 2
chmod +x stream.sh
./stream.sh
```

When prompted for an IP, press Enter for localhost. For the source, choose 3
(test pattern). A window with colour bars should appear.

## Remote streaming (two machines)

On the receiver:

```bash
./view.sh
```

Find its IP with `ip addr` or `hostname -I`.

On the sender:

```bash
./stream.sh
```

Enter the receiver's IP and choose a source (1 = camera, 3 = test pattern).

## How it works

1. `setup.sh` installs GStreamer and opens UDP port 5004.
2. `stream.sh` asks for the destination IP, detects an encoder, and sends video.
3. `view.sh` detects a decoder, receives the stream, and shows a window.

## Encoder detection

The scripts pick the best available encoder and fall back to software if the
hardware path fails:

- NVIDIA GPU - `nvh264enc`
- Intel/AMD GPU - `vaapih264enc`
- No GPU - `x264enc` (software, higher CPU)

## Troubleshooting

No video window:

```bash
killall gst-launch-1.0
# Start the viewer first, then the streamer.
```

Camera not found:

```bash
ls /dev/video*   # confirm the camera exists, or use the test pattern
```

Cannot reach the remote IP:

```bash
sudo ufw allow 5004/udp
ping <other-ip>
```

Port already in use:

```bash
sudo netstat -tulpn | grep 5004
killall gst-launch-1.0
```

See [COMPATIBILITY.md](./COMPATIBILITY.md) for the encoder/decoder matrix.
