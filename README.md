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
3. `view.sh` receives the stream and displays it; `decodebin` selects the
   decoder.

## Encoder detection

`stream.sh` picks the first encoder that is installed and actually works on the
machine, and falls back to software otherwise:

- NVIDIA desktop GPU - `nvh264enc`
- NVIDIA Jetson / Orin - `nvv4l2h264enc`
- Intel/AMD GPU (VA plugin) - `vah264enc`
- Intel GPU (QuickSync) - `qsvh264enc`
- Intel/AMD GPU (legacy VA-API) - `vaapih264enc`
- ARM boards (Pi, i.MX, Qualcomm, Rockchip) - `v4l2h264enc`
- No hardware - `x264enc` (software, higher CPU)

## Decoder selection

`view.sh` does not detect decoders by hand. `decodebin` auto-plugs the best
available decoder (NVIDIA, VA, VA-API, Jetson `nvv4l2decoder`, ARM V4L2
decoders) and, if a hardware decoder rejects a stream or is unavailable, retries
down to software on its own.

The camera and test-pattern sources are always re-encoded. A video file is
decoded with `decodebin` and re-encoded too, so any container or codec (MP4,
MKV, AVI, HEVC, ...) works.

## Configuration

Override defaults with environment variables:

```bash
PORT=6000 ./view.sh              # listen on a different port
PORT=6000 ./stream.sh            # must match the viewer
LATENCY=100 ./view.sh            # jitter buffer in ms (default 50)
BITRATE=6000 ./stream.sh         # encode bitrate in kbps (default 3000)
CODEC=h265 ./view.sh             # H.265/HEVC instead of H.264
CODEC=h265 ./stream.sh           # both ends must use the same codec
```

`CODEC` defaults to `h264` (widest interop). `h265` gives better compression at
the cost of more CPU on software paths; the viewer and streamer must match.

## Platforms

Runs on x86 (NVIDIA/Intel/AMD or CPU) and ARM boards: Raspberry Pi, NVIDIA
Jetson/Orin, NXP i.MX, Qualcomm, and Rockchip. On ARM the encoder uses the
board's V4L2 hardware codec (Jetson uses `nvv4l2`); the viewer's `decodebin`
picks the matching hardware decoder. Install GStreamer with `setup.sh` on
Debian/Ubuntu-based systems (including Raspberry Pi OS and Jetson L4T), or via
the board BSP on Yocto systems.

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
