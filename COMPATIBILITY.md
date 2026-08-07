# Compatibility

`stream.sh` picks the best working encoder; `view.sh` lets `decodebin` pick the
decoder. Any encoder interoperates with any decoder.

Codec is selected with `CODEC=h264` (default) or `CODEC=h265`; both ends must
match. Everything below applies to both codecs (element names swap 264 for 265).

## How it works

`stream.sh` (encoder):

1. Walks a priority list: NVIDIA desktop, Jetson (`nvv4l2`), VA, QuickSync,
   VA-API, ARM V4L2, software.
2. Tests that the encoder actually works, not just that the plugin is present.
3. Uses the first that works.
4. Falls back to software (`x264enc`/`x265enc`) if the hardware path fails.

`view.sh` (decoder):

1. Receives the RTP/UDP stream and hands the elementary stream to `decodebin`.
2. `decodebin` auto-plugs the highest-ranked decoder for the hardware.
3. On a hardware decode failure (for example an unsupported profile) it retries
   the next candidate on its own, down to software.

## RTSP relay

An IP camera source (`stream.sh` option 4) bypasses this entirely. The camera
already emits H.264/H.265, so the stream is depayloaded and repayloaded without
decoding, no encoder is selected, and the probe above is skipped. It therefore
works on any board with GStreamer, hardware codec or not. `TRANSCODE=1` opts
back into the table below.

## Containers

Hardware encoding inside a container needs the host's codec userspace, which is
injected at runtime rather than shipped in the image, so the container base has
to match the host. On Jetson/Orin that means an L4T image matching the host L4T
and `--runtime nvidia` (nvidia-container-toolkit); a plain distro image encodes
on the CPU. A relay needs none of this.

## Encoder/decoder matrix

Rows are the streamer's encoder, columns are the decoder `decodebin` selects on
the viewer. HW means a hardware decoder is used, SW means it falls back to
software decode. All combinations play.

| Encoder \ Decoder | NVIDIA | QuickSync | VA / VA-API | Software |
| ----------------- | ------ | --------- | ----------- | -------- |
| NVIDIA            | HW     | HW        | SW          | SW       |
| VA / VA-API       | HW     | HW        | HW          | SW       |
| QuickSync         | HW     | HW        | HW          | SW       |
| Software          | HW     | HW        | HW          | SW       |

The NVIDIA encoder can emit profiles (for example high-4:4:4) that some
hardware decoders reject; `decodebin` then falls back to software decode. Video
still plays, with slightly higher CPU on the viewer.

## Encoders by platform

Element names shown for H.264; H.265 swaps `264` for `265` (for example
`nvh265enc`, `nvv4l2h265enc`, `x265enc`).

| Encoder       | Platform             | Notes                |
| ------------- | -------------------- | -------------------- |
| nvh264enc     | NVIDIA desktop       | bitrate kbps         |
| nvv4l2h264enc | NVIDIA Jetson / Orin | NVMM, bitrate b/s    |
| vah264enc     | Intel/AMD (VA)       | preferred over vaapi |
| qsvh264enc    | Intel QuickSync      |                      |
| vaapih264enc  | Intel/AMD (legacy)   |                      |
| v4l2h264enc   | ARM (Pi/i.MX/QCom)   | driver bitrate       |
| x264enc       | any CPU (software)   | always available     |

## Decoder support

`decodebin` chooses among whatever is installed:

| Decoder                 | Platform             | Notes               |
| ----------------------- | -------------------- | ------------------- |
| nvh264dec               | NVIDIA desktop       | may reject profiles |
| nvv4l2decoder           | NVIDIA Jetson / Orin | NVMM output         |
| vah264dec               | Intel/AMD (VA)       |                     |
| vaapih264dec            | Intel/AMD (legacy)   | rejects high-4:4:4  |
| v4l2\*dec / v4l2sl\*dec | ARM (Pi/i.MX/QCom)   |                     |
| avdec_h264              | any CPU (software)   | always works        |

## Fallback order

Streamer: first working hardware encoder from the priority list, then software.

Viewer: `decodebin` tries hardware decoders by rank and retries down to software
automatically.

## Approximate CPU usage

| Path            | CPU    |
| --------------- | ------ |
| Hardware encode | 5-15%  |
| Software encode | 30-50% |
| Hardware decode | 3-10%  |
| Software decode | 15-30% |

## Testing your setup

```bash
# Terminal 1
./view.sh

# Terminal 2
./stream.sh
# Press Enter for localhost, then choose 3 for the test pattern.
```

`decodebin` picks the decoder silently. For some encoder/decoder pairs it uses a
software decoder; that is expected and still works.

## Troubleshooting

No window appears:

```bash
killall gst-launch-1.0
# Start the viewer first, then the streamer.
```

Nothing decodes:

```bash
ps aux | grep gst-launch
sudo netstat -tulpn | grep 5004
```

The streamer logs to `/tmp/stream_error.log`. Run `view.sh` with `-v` output
visible to see which decoder `decodebin` chose.

Encoder test shows `[--]` but a GPU is present: the plugin is installed but the
driver is not working, the GPU is disabled in BIOS, or the driver version is
wrong. The streamer falls back to software automatically.
