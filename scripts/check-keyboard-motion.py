"""Track the actual history toolbar in the composited simulator video, including its first frame."""
import json
import subprocess
import sys


def main(video):
    info = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0",
                                    "-show_entries", "stream=width,height", "-of", "json", video])
    stream = json.loads(info)["streams"][0]
    height = 2 * int(0.5 + (201 * stream["height"] / stream["width"]) / 2)
    # On the test iPhone, one sampled pixel corresponds to two screen points.
    # This narrow strip crosses the blue toolbar trash icon and the fixture's magenta marker.
    filters = f"scale=201:{height},crop=8:ih:iw-20:0,settb=1/30,setpts=N"
    decoder = subprocess.Popen(["ffmpeg", "-v", "error", "-i", video, "-an", "-vf", filters,
                                "-enc_time_base", "1:30", "-fps_mode", "passthrough", "-pix_fmt", "rgb24",
                                "-f", "rawvideo", "pipe:1"], stdout=subprocess.PIPE)
    stride = 8 * 3
    positions = []
    system_frames = 0
    try:
        while frame := decoder.stdout.read(stride * height):
            if len(frame) != stride * height:
                raise SystemExit("Incomplete simulator video frame")
            def magenta(index):
                r, g, b = frame[index:index + 3]
                return r > 185 and g < 90 and b > 185
            if not any(all(magenta(y * stride + x * 3) for x in (1, 4, 6))
                       for y in range(0, height // 3)):
                continue
            rows = []
            for y in range(height // 4, height * 9 // 10):
                blue = 0
                for index in range(y * stride, (y + 1) * stride, 3):
                    r, g, b = frame[index:index + 3]
                    blue += b > 105 and b - r > 55 and b - g > 18
                if blue >= 2:
                    rows.append(y)
            if 5 <= len(rows) <= 14 and rows[-1] - rows[0] <= 14:
                positions.append((rows[0] + rows[-1]) / 2)
            elif not positions:
                system_frames += 1
    finally:
        decoder.stdout.close()
        status = decoder.wait()
    if status or system_frames < 2 or len(positions) < 2:
        raise SystemExit(f"Missing visual handoff: decoder={status}, native={system_frames}, toolbar={len(positions)}")
    drift = max(positions) - min(positions)
    print(f"Visible history toolbar: {len(positions)} frames, first={positions[0]}, "
          f"last={positions[-1]}, max movement={drift} sampled pixels", flush=True)
    if drift > 2:
        raise SystemExit("The visible keyboard controls moved by more than four points during the handoff")


if __name__ == "__main__":
    main(sys.argv[1])
