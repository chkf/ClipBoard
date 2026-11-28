"""Verify the keyboard's composited candidate strip, record rows and input-mode handoff."""
import json
from pathlib import Path
from statistics import median
import subprocess
import sys


def attachment(directory, title):
    groups = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    matches = [item for group in groups for item in group.get("attachments", [])
               if title in item.get("suggestedHumanReadableName", "")]
    if not matches:
        raise ValueError(f"Missing XCTest attachment: {title}")
    return directory / matches[-1]["exportedFileName"]


def image(path, width, height):
    data = subprocess.check_output(["ffmpeg", "-v", "error", "-i", path, "-frames:v", "1", "-vf",
        f"scale={width}:{height}:flags=area", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"])
    if len(data) != width * height * 3:
        raise ValueError(f"Incomplete screenshot: {path}")
    return data


class Glyph:
    def __init__(self, gray, stride, box):
        self.stride = stride
        self.x, self.y, self.width, self.height = box
        patch = self.patch(gray, 0)
        bg = median(patch)
        bright = max(patch) - bg > bg - min(patch)
        contrast = max(max(patch) - bg, bg - min(patch))
        if contrast < 35:
            raise ValueError(f"No visible glyph inside {box}, contrast {contrast}")
        step = max(25, contrast * 0.38)
        self.table = bytes(255 if (n - bg if bright else bg - n) > step else 0 for n in range(256))
        ink = patch.translate(self.table)
        points = [(i % self.width, i // self.width) for i, p in enumerate(ink) if p]
        self.bounds = (max(x for x, _ in points) - min(x for x, _ in points) + 1,
                       max(y for _, y in points) - min(y for _, y in points) + 1)
        self.reference = int.from_bytes(ink, "big")
        self.bits = self.reference.bit_count()

    def patch(self, gray, dy):
        return b"".join(gray[(y + dy) * self.stride + self.x:(y + dy) * self.stride + self.x + self.width]
                        for y in range(self.y, self.y + self.height))

    def score(self, gray, dy):
        bits = int.from_bytes(self.patch(gray, dy).translate(self.table), "big")
        return 2 * (self.reference & bits).bit_count() / (self.bits + bits.bit_count())


class Surface:
    def __init__(self, directory, geometry_name, screenshot_name):
        self.rect = json.loads(attachment(directory, geometry_name).read_text(encoding="utf-8"))
        _, _, w, h = self.rect["screen"]
        self.width, self.height = round(w), round(h)
        self.rgb = image(attachment(directory, screenshot_name), self.width, self.height)
        gray = self.rgb[::3]
        ax, ay, aw, ah = self.rect["arrow"]
        cx, cy, cw, ch = self.rect["category"]
        rx, ry, rw, rh = self.rect["row"]
        if not (h/2 < ay < h - 120 and rw > w * .94):
            raise ValueError(f"Invalid on-screen surface geometry: {self.rect}")
        self.arrow = Glyph(gray, self.width, (round(ax + aw/2) - 12, round(ay + ah/2) - 9, 24, 18))
        self.category = Glyph(gray, self.width, (round(cx + 3), round(cy + ch/2) - 14, round(cw - 6), 28))
        self.first_row = Glyph(gray, self.width, (round(rx + 8), round(ry + rh/2) - 12, 58, 24))

    def pixel(self, data, x, y):
        i = 3 * (round(y) * self.width + round(x))
        return tuple(data[i:i+3])


def appearance(directory):
    surface = Surface(directory, "ClipboardSurfaceGeometry", "ClipboardEmptySearch")
    native = image(attachment(directory, "NativeEmptySearch"), surface.width, surface.height)
    x, y, width, height = surface.rect["arrow"]
    row_height = surface.rect["row"][3]
    aw, ah = surface.arrow.bounds
    _, text_height = surface.category.bounds
    print(f"Category ink {text_height} pt, chevron {aw} × {ah} pt, row {row_height:g} pt", flush=True)
    if not (15 <= text_height <= 24 and 10 <= aw <= 19 and 5 <= ah <= 13 and width >= 43 and height >= 44):
        raise ValueError("The candidate text or the disclosure differs from the approved size")
    reference = surface.pixel(native, surface.width * .52, surface.height * .95)
    for index in range(4):
        for fraction in (.67, .82, .96):
            actual = surface.pixel(surface.rgb, surface.width * fraction, y + height + (index + .37) * row_height)
            if max(abs(a - b) for a, b in zip(actual, reference)) > 15:
                raise ValueError(f"Record {index + 1} at {fraction:g} has fill {actual}, native background {reference}")


def inspect_recording(video, surface, minimum_native):
    w, h = surface.width, surface.height
    decoder = subprocess.Popen(["ffmpeg", "-v", "error", "-i", video, "-an", "-vf",
        f"scale={w}:{h}:flags=area,settb=1/30,setpts=N", "-enc_time_base", "1:30", "-fps_mode", "passthrough",
        "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"], stdout=subprocess.PIPE)
    shifts = sorted(range(-10, 11), key=abs)
    first = None
    offsets, missing = [], []
    native_frames = blank = frame_number = 0
    try:
        while frame := decoder.stdout.read(w*h*3):
            if len(frame) != w*h*3:
                raise ValueError("Incomplete video frame")
            frame_number += 1
            marker = round(w * .94) * 3
            if not any(frame[p] > 185 and frame[p + 1] < 90 and frame[p + 2] > 185
                       for p in range(marker, (h // 3) * w * 3, w*3)):
                continue
            gray = frame[::3]
            score, dy = max(((surface.arrow.score(gray, shift), shift) for shift in shifts), key=lambda pair: pair[0])
            if score < .67:
                if first is None:
                    native_frames += 1
                else:
                    blank += 1
                continue
            if blank:
                raise ValueError(f"The visible category strip disappeared for {blank} frames")
            if first is None:
                first = frame_number - 1
            offsets.append(dy)
            if surface.category.score(gray, dy) < .60 or surface.first_row.score(gray, dy) < .56:
                missing.append(frame_number)
    finally:
        decoder.stdout.close()
        status = decoder.wait()
    if status or first is None or len(offsets) < 2 or native_frames < minimum_native:
        raise ValueError(f"Incomplete handoff: decoder={status}, system frames={native_frames}, Clipboard frames={len(offsets)}")
    if missing or blank or max(offsets) - min(offsets) > 4:
        raise ValueError(f"Unstable history: missing text on {missing[:12]}, final missing={blank}, offsets={set(offsets)}")
    print(f"First history row and category visible on all {len(offsets)} chevron frames; vertical travel "
          f"{max(offsets)-min(offsets)} pt", flush=True)
    return first


def motion(directory, video, preview):
    surface = Surface(directory, "ClipboardMotionGeometry", "ClipboardMotionReference")
    first = inspect_recording(video, surface, 2)
    frames = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "frame=best_effort_timestamp_time", "-of", "json", video]))["frames"]
    start = first
    while start > 0 and float(frames[first]["best_effort_timestamp_time"]) - float(frames[start-1]["best_effort_timestamp_time"]) <= .5:
        start -= 1
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", video, "-an", "-vf",
        f"trim=start_frame={start},setpts=PTS-STARTPTS,scale=480:-2,fps=30", "-t", "3.5", "-c:v", "libx264",
        "-crf", "19", "-pix_fmt", "yuv420p", "-movflags", "+faststart", preview], check=True)
    inspect_recording(preview, surface, 0)


if __name__ == "__main__":
    mode, folder, *extra = sys.argv[1:]
    if mode == "appearance":
        appearance(Path(folder))
    elif mode == "motion":
        motion(Path(folder), *extra)
    else:
        raise SystemExit("Expected appearance or motion")
