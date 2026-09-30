# Local video_compress 3.1.4 patch

Source: `video_compress` 3.1.4 from pub.dev, retained under its bundled LICENSE.

- Android `com.otaliastudios:transcoder` is updated from 0.10.5 to 0.11.2.
  Transcoder 0.11.0 changed the pipeline and lists a fix for pipeline stalls.
  R2-4 captured an Android 0.10.5 deadlock in `eglSwapBuffers`.
- `MonotonicTimeInterpolator` repairs decoded frame timestamps that arrive out
  of order. Without it, 0.11.2 rejected the R2-4 screen recording at 0.03 s
  after receiving a 0.065 s frame. Its behavior is covered by a Kotlin unit
  test; the resulting MP4 was decoded with `ffmpeg` on the R2-4 sample.
- Dart `compressVideo` now clears its busy flag in `finally` when the native
  MethodChannel call settles or fails. It deliberately keeps the flag set while
  a cancelled native call remains blocked.
- Android video strategies cap output at 15 fps before frames reach the encoder.
  The 30 fps R2-5 fixture still stalled with Transcoder 0.11.2 at the encoder
  input surface; this reduces that surface's load at the cost of frame rate.
- Android output paths use unique names. Cancellation unlinks the partial MP4
  immediately because a blocked codec may never invoke its cancellation
  callback; failure and late completion also discard the abandoned file.
- Android thumbnail extraction tries nearby frames if the requested sync frame
  is unavailable and returns one channel error if no frame can be decoded.
  Previously that path returned an unsupported `Integer[]` and then crashed on
  a null bitmap.

The app's `ImageProcessor` also blocks later videos while a timed-out native
call remains unsettled. This prevents another compression attempt from
colliding with an encoder still held by the plugin.

On the available Android emulator, five consecutive picks of the R2-4 video
completed in one app process. Transcoder 0.11.2 still stalled on the 30 fps
R2-5 fixture in four of four beta attempts. With the 15 fps cap, three
consecutive picks of that fixture produced complete MP4s in one process; the
first decoded with `ffmpeg` as 90 frames over about six seconds. The 4:4:4
fixture also produced a complete 46-frame MP4. A real Android handset has not
yet been tested. The timeout guard and later-pick feedback are covered by host
tests; a new native stall has not been observed after the frame-rate cap.
