# Compatibility

The scripts detect available hardware and fall back to software, so any encoder
can stream to any decoder.

## How it works

`stream.sh` (encoder):

1. Detects hardware in order: NVIDIA, QuickSync, VA-API, software.
2. Tests that the hardware actually works, not just that the plugin is present.
3. Uses the best working encoder, producing baseline/main profile H.264.
4. Falls back to software (x264enc) if the hardware path fails.

`view.sh` (decoder):

1. Detects hardware in the same order.
2. Tests that it works.
3. Falls back to software (avdec_h264), then to a minimal pipeline.

## Encoder/decoder matrix

Rows are the streamer, columns are the viewer. HW means hardware decode, SW
means the viewer falls back to software decode.

| Streamer \ Viewer | NVIDIA | QuickSync | VA-API | Software |
| ----------------- | ------ | --------- | ------ | -------- |
| NVIDIA            | HW     | HW        | SW     | SW       |
| QuickSync         | HW     | HW        | HW     | SW       |
| VA-API            | HW     | HW        | HW     | SW       |
| Software          | HW     | HW        | HW     | SW       |

The NVIDIA encoder can emit profiles (for example high-4:4:4) that some
hardware decoders reject; the viewer then falls back to software decode. Video
still plays, with slightly higher CPU on the viewer.

## Encoder output

| Encoder      | Format | Profile              | Notes                    |
| ------------ | ------ | -------------------- | ------------------------ |
| nvh264enc    | I420   | variable             | may need software decode |
| qsvh264enc   | NV12   | main/high            | all hardware decoders    |
| vaapih264enc | NV12   | constrained-baseline | forced for compatibility |
| x264enc      | I420   | main/high            | all decoders             |

## Decoder support

| Decoder      | Profiles handled     | Notes                    |
| ------------ | -------------------- | ------------------------ |
| nvh264dec    | most                 | may reject some profiles |
| qsvh264dec   | most                 |                          |
| vaapih264dec | baseline, main, high | rejects high-4:4:4       |
| avdec_h264   | all                  | software, always works   |

## Fallback order

Streamer: hardware encoder, then software encoder.

Viewer: hardware decoder, then software decoder (standard pipeline), then a
minimal software pipeline.

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

If the viewer reports a hardware decode failure followed by "Switching to
software decoder", that is expected for some encoder/decoder pairs and still
works.

## Troubleshooting

No window appears:

```bash
killall gst-launch-1.0
# Start the viewer first, then the streamer.
```

All decoder attempts failed:

```bash
cat /tmp/viewer_error.log
ps aux | grep gst-launch
sudo netstat -tulpn | grep 5004
```

Hardware test shows `[--]` but a GPU is present: the plugin is installed but the
driver is not working, the GPU is disabled in BIOS, or the driver version is
wrong. The scripts fall back to software automatically.
