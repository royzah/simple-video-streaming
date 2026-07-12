# Compatibility

`stream.sh` picks the best working encoder; `view.sh` lets `decodebin` pick the
decoder. Any encoder interoperates with any decoder.

## How it works

`stream.sh` (encoder):

1. Walks a priority list: NVIDIA, VA, QuickSync, VA-API, software.
2. Tests that the encoder actually works, not just that the plugin is present.
3. Uses the first that works, producing widely compatible H.264.
4. Falls back to software (x264enc) if the hardware path fails at runtime.

`view.sh` (decoder):

1. Receives the RTP/UDP stream and hands the H.264 to `decodebin`.
2. `decodebin` auto-plugs the highest-ranked decoder for the hardware.
3. On a hardware decode failure (for example an unsupported profile) it retries
   the next candidate on its own, down to software (`avdec_h264`).

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

## Encoder output

| Encoder      | Format | Profile              | Notes                    |
| ------------ | ------ | -------------------- | ------------------------ |
| nvh264enc    | I420   | variable             | may need software decode |
| vah264enc    | NV12   | main/high            | modern VA plugin         |
| qsvh264enc   | NV12   | main/high            | all hardware decoders    |
| vaapih264enc | NV12   | constrained-baseline | forced for compatibility |
| x264enc      | I420   | main/high            | all decoders             |

## Decoder support

`decodebin` chooses among whatever is installed:

| Decoder      | Profiles handled     | Notes                    |
| ------------ | -------------------- | ------------------------ |
| nvh264dec    | most                 | may reject some profiles |
| vah264dec    | most                 | modern VA plugin         |
| vaapih264dec | baseline, main, high | rejects high-4:4:4       |
| avdec_h264   | all                  | software, always works   |

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
