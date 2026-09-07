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

Enter the receiver's IP and choose a source (1 = camera, 3 = test pattern,
4 = IP camera over RTSP).

## IP camera (RTSP)

Choose source 4 and give the camera's URL. The camera already sends H.264 or
H.265, so the stream is **relayed unchanged**: nothing is decoded or encoded, no
GPU is touched, and it runs on a board with no hardware encoder at all.

```bash
CODEC=h264 ./stream.sh        # must match what the camera sends
TRANSCODE=1 ./stream.sh       # only if you need to change codec or bitrate
```

RTSP is pulled over TCP so the whole session stays on the camera's port instead
of spraying RTP across UDP ports a firewall has not opened.

## Container

Built for `amd64` and `arm64` and published to
`ghcr.io/royzah/simple-video-streaming`. Every prompt is skipped when its
variable is set, so the same scripts run unattended:

| Variable     | Replaces the prompt for            |
| ------------ | ---------------------------------- |
| `DEST_IP`    | destination IP                     |
| `SOURCE`     | `camera`, `file`, `test`, `rtsp`   |
| `CAMERA`     | which `/dev/video*` to use         |
| `VIDEO_FILE` | file path                          |
| `RTSP_URL`   | IP camera URL                      |

Leave one unset and it still asks, so nothing changes outside a container.

```bash
IMAGE=ghcr.io/royzah/simple-video-streaming:latest

# viewer: needs an X display
docker run --rm --network host -e DISPLAY="$DISPLAY" \
  -v /tmp/.X11-unix:/tmp/.X11-unix:ro $IMAGE /app/view.sh

# streamer: USB webcam
docker run --rm --network host --device /dev/video0 \
  -e DEST_IP=<viewer ip> -e SOURCE=camera -e CAMERA=/dev/video0 \
  $IMAGE /app/stream.sh

# streamer: IP camera, relayed without re-encoding
docker run --rm --network host \
  -e DEST_IP=<viewer ip> -e SOURCE=rtsp -e RTSP_URL=rtsp://<cam>/stream \
  $IMAGE /app/stream.sh
```

`--network host` keeps RTP on the host's own address. On a bridge, give the
viewer's container IP as `DEST_IP` and the sender needs no published port.

## On a TII saluki

The saluki image ships no GStreamer, and app code does not belong in its rootfs,
so **run the container above**, with `podman` rather than `docker`:

```bash
sudo podman run --rm --network host --device /dev/video0 \
  -e DEST_IP=<laptop address> -e SOURCE=camera -e CAMERA=/dev/video0 \
  ghcr.io/royzah/simple-video-streaming:latest /app/stream.sh
```

The board is an Orin NX. **The hardware encoder is not used here**: a webcam is
re-encoded on the CPU, and an IP camera is relayed untouched. Reaching
`nvv4l2h264enc` would need an L4T base image matching the host and
`--runtime nvidia`, which this image deliberately does not carry.

The saluki reaches its LAN through the net-vm guest, which routes and
masquerades for it, so the container pulls a camera on that LAN with no extra
configuration.

The board's camera lane has no DHCP, so give the camera a static address on that
lane. A lane reaches the mission computer only, never the fabric, so the saluki
pulls from the camera and re-publishes to the laptop; the camera never talks to
the laptop directly.

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
MKV, AVI, HEVC, ...) works. An RTSP source is relayed as-is unless
`TRANSCODE=1`.

## Configuration

Override defaults with environment variables:

```bash
PORT=6000 ./view.sh              # listen on a different port
PORT=6000 ./stream.sh            # must match the viewer
LATENCY=100 ./view.sh            # jitter buffer in ms (default 50)
BITRATE=6000 ./stream.sh         # encode bitrate in kbps (default 3000)
CODEC=h265 ./view.sh             # H.265/HEVC instead of H.264
CODEC=h265 ./stream.sh           # both ends must use the same codec
TRANSCODE=1 ./stream.sh          # re-encode an RTSP source instead of relaying
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

An IP camera is never a `/dev/video*` device; use source 4 with its RTSP URL.

RTSP source connects but no video: the camera's codec does not match `CODEC`.
Relaying cannot convert it, so set `CODEC` to what the camera sends or use
`TRANSCODE=1`.

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
