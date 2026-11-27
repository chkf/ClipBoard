"""Track the actual history toolbar in the composited simulator video, including its first frame."""
import json
from itertools import groupby
from pathlib import Path
import subprocess
import sys


def space_bar_ink(frame, width, height):
    # Compare the middle of the space bar with an empty part of the same face on each scan line.
    ink = 0
    for y in range(round(height * 0.875), round(height * 0.904)):
        row = y * width * 3
        side = row + round(width * 0.35) * 3
        background = frame[side:side + 3]
        for x in range(round(width * 0.40), round(width * 0.60)):
            p = row + x * 3
            if max(abs(a - b) for a, b in zip(frame[p:p+3], background)) > 20:
                ink += 1
    return ink


def command_key_position(frame, width, height):
    # Three equal command keys occupy the same trailing gutter. On Apple's letter
    # keyboard the second row is inset. Track the rail even before history loads.
    red = frame[::3]
    gap = round(width * .855)
    face_left, face_right = round(width * .885), round(width * .97)
    matches = []
    for y in range(height // 4, height * 9 // 10):
        row = y * width
        fill = red[row + face_left]
        if fill - min(red[row + gap - 1:row + gap + 2]) < 13 or abs(red[row + face_right] - fill) > 7:
            continue
        matches.append(y)
    bands = []
    for _, group in groupby(enumerate(matches), key=lambda item: item[1] - item[0]):
        rows = [y for _, y in group]
        if 12 <= len(rows) <= 27:
            bands.append(rows)
    for first, middle, last in zip(bands, bands[1:], bands[2:]):
        step = middle[0] - first[0]
        if not 22 <= step <= 31 or abs(last[0] - middle[0] - step) > 2:
            continue
        icon_left, icon_right = round(width * .90), round(width * .96)
        for y in first[2:-2]:
            row = y * width
            fill = red[row + face_left]
            if any(abs(value - fill) > 24 for value in red[row + icon_left:row + icon_right]):
                return (first[0] + first[-1]) / 2
    return None


def save_preview(video, first_frame, destination):
    frames = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "frame=best_effort_timestamp_time", "-of", "json", video]))["frames"]
    first_time = float(frames[first_frame]["best_effort_timestamp_time"])
    start = first_frame
    while start > 0 and float(frames[start - 1]["best_effort_timestamp_time"]) >= first_time - 0.5:
        start -= 1
    Path(destination).parent.mkdir(parents=True, exist_ok=True)
    # Select the actual decoded frame. A time-based seek can land in another scene
    # when a simctl screen recording has a nonzero start time or a QuickTime edit list.
    filters = f"trim=start_frame={start},setpts=PTS-STARTPTS,scale=480:-2,fps=30"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", video, "-t", "3.5",
                    "-an", "-vf", filters, "-c:v", "libx264", "-crf", "19", "-pix_fmt", "yuv420p",
                    "-movflags", "+faststart", destination], check=True)


def inspect_recording(video, minimum_native_frames):
    info = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0",
                                    "-show_entries", "stream=width,height", "-of", "json", video])
    stream = json.loads(info)["streams"][0]
    height = 2 * int(0.5 + (201 * stream["height"] / stream["width"]) / 2)
    # On the test iPhone, one sampled pixel corresponds to two screen points.
    width = 201
    # The fixture draws a magenta marker near the upper trailing corner while measuring.
    rail = range(width - 20, width - 12)
    filters = f"scale={width}:{height},settb=1/30,setpts=N"
    decoder = subprocess.Popen(["ffmpeg", "-v", "error", "-i", video, "-an", "-vf", filters,
                                "-enc_time_base", "1:30", "-fps_mode", "passthrough", "-pix_fmt", "rgb24",
                                "-f", "rawvideo", "pipe:1"], stdout=subprocess.PIPE)
    stride = width * 3
    positions = []
    space_ink = []
    system_frames = 0
    first_visible_frame = None
    frame_index = -1
    try:
        while frame := decoder.stdout.read(stride * height):
            frame_index += 1
            if len(frame) != stride * height:
                raise SystemExit("Incomplete simulator video frame")
            def magenta(index):
                r, g, b = frame[index:index + 3]
                return r > 185 and g < 90 and b > 185
            if not any(all(magenta(y * stride + (rail.start + x) * 3) for x in (1, 4, 6))
                       for y in range(0, height // 3)):
                continue
            position = command_key_position(frame, width, height)
            if position is not None:
                if first_visible_frame is None:
                    first_visible_frame = frame_index
                positions.append(position)
                space_ink.append(space_bar_ink(frame, width, height))
            elif not positions:
                system_frames += 1
    finally:
        decoder.stdout.close()
        status = decoder.wait()
    if status or system_frames < minimum_native_frames or len(positions) < 2:
        raise SystemExit(f"Missing visual handoff: decoder={status}, native={system_frames}, toolbar={len(positions)}")
    drift = max(positions) - min(positions)
    print(f"Visible history toolbar: {len(positions)} frames, first={positions[0]}, "
          f"last={positions[-1]}, max movement={drift} sampled pixels", flush=True)
    if drift > 2:
        raise SystemExit("The visible keyboard controls moved by more than four points during the handoff")
    labelled = [i for i, ink in enumerate(space_ink) if ink >= 12]
    if not labelled or len(space_ink) - labelled[-1] < 3 or max(space_ink[-2:]) > 3:
        raise SystemExit(f"The space bar must first display the input mode name and then clear: {space_ink}")
    print(f"Space bar name visible in {len(labelled)} frames; final plain key ink counts: {space_ink[-2:]}")
    return first_visible_frame


if __name__ == "__main__":
    video, *previews = sys.argv[1:]
    first_frame = inspect_recording(video, minimum_native_frames=2)
    if previews:
        destination, = previews
        save_preview(video, first_frame, destination)
        inspect_recording(destination, minimum_native_frames=0)
