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
sudo ./setup.sh
```

## Local test (one machine, two terminals)

```bash
# Terminal 1
./view.sh

# Terminal 2
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
- Intel GPU (QuickSync) - `qsvh264enc`
- Intel/AMD GPU (VA-API) - `vaapih264enc`
- No GPU - `x264enc` (software, higher CPU)

The camera and test-pattern sources are always re-encoded to H.264. A video
file is decoded with `decodebin` and re-encoded too, so any container or codec
(MP4, MKV, AVI, HEVC, ...) works.

## Configuration

Override defaults with environment variables:

```bash
PORT=6000 ./view.sh              # listen on a different port
PORT=6000 ./stream.sh            # must match the viewer
LATENCY=100 ./view.sh            # jitter buffer in ms (default 50)
BITRATE=6000 ./stream.sh         # encode bitrate in kbps (default 3000)
```

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
