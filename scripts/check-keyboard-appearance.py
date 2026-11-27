"""Compare the painted keys in the two original XCTest search-field screenshots."""
import json
from collections import deque
from pathlib import Path
from statistics import median
import subprocess
import sys


class Screen:
    def __init__(self, path):
        size = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                        "stream=width,height", "-of", "csv=s=x:p=0", str(path)], text=True)
        # Both portrait iPhones in the UI test matrix have three device pixels per point.
        self.width, self.height = (int(n) // 3 for n in size.strip().split("x"))
        self.pixels = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(path), "-frames:v", "1",
            "-vf", f"scale={self.width}:{self.height}:flags=area", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"])
        assert len(self.pixels) == self.width * self.height * 3

    def color(self, x, y):
        offset = (y * self.width + x) * 3
        return self.pixels[offset:offset + 3]

    def matches(self, x, y, color):
        return all(abs(a - b) <= 4 for a, b in zip(self.color(x, y), color))

    def region(self, x, y, width, height):
        return [self.color(i, j) for j in range(y, y + height) for i in range(x, x + width)]

    def sample_y(self):
        w, h = self.width, self.height
        # Find the wide space cap, then sample above the system's corner language indicator.
        for y in range(h - 1, h * 3 // 4, -1):
            left = right = w * 42 // 100
            color = self.color(left, y)
            while left > 0 and self.matches(left - 1, y, color):
                left -= 1
            while right + 1 < w and self.matches(right + 1, y, color):
                right += 1
            if (w // 5 <= left < w // 3 and w * 2 // 3 <= right < w * 4 // 5
                    and self.matches(w * 8 // 100, y, color) and self.matches(w * 35 // 100, y - 3, color)):
                while y > 0 and self.matches(w * 35 // 100, y - 1, color):
                    y -= 1
                return y + 8
        raise ValueError("Could not locate the space bar in the screenshot")

    def face(self, x, y):
        # Follow the connected key surface around labels, including the native 123 glyph.
        color = self.color(x, y)
        queue = deque([(x, y)])
        visited = {(x, y)}
        left = right = x
        top = bottom = y
        while queue:
            x, y = queue.popleft()
            left, right = min(left, x), max(right, x)
            top, bottom = min(top, y), max(bottom, y)
            for u, v in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if (u, v) in visited or not (0 <= u < self.width and 0 <= v < self.height):
                    continue
                visited.add((u, v))
                if self.matches(u, v, color):
                    queue.append((u, v))
        if right - left < 20 or bottom - top < 20 or bottom - top > 65:
            raise ValueError(f"Could not isolate the key face: {(left, top, right, bottom)}")
        return left, top, right + 1, bottom + 1

    def measurements(self):
        y = self.sample_y()
        results = {}
        for name, fraction in (("123", .075), ("Emoji", .19), ("Space", .49), ("Search", .87)):
            rect = self.face(int(self.width * fraction), y)
            l, t, r, b = rect
            cx, cy = (l + r) // 2, (t + b) // 2
            fill = tuple(map(median, zip(*self.region(l + 5, t + 5, r - l - 10, b - t - 10))))
            results[name + " bounds"] = rect
            results[name + " fill"] = fill
            if name == "Space":
                results["keyboard background"] = tuple(map(median, zip(*self.region(cx - 8, t - 7, 16, 4))))
            if name == "Search":
                center = self.region(cx - 17, cy - 15, 34, 30)
                center.sort(key=lambda rgb: sum(abs(a - b) for a, b in zip(rgb, fill)))
                results["disabled search symbol"] = tuple(center[len(center) * 98 // 100])
        return results


def screenshots(directory):
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    images = {}
    for group in manifest:
        for item in group.get("attachments", []):
            for title in ("NativeEmptySearch", "ClipboardEmptySearch"):
                if title in item.get("suggestedHumanReadableName", "") and item.get("exportedFileName", "").lower().endswith(".png"):
                    images[title] = directory / item["exportedFileName"]
    return images["NativeEmptySearch"], images["ClipboardEmptySearch"]


if __name__ == "__main__":
    paths = [Path(arg) for arg in sys.argv[1:]]
    native, clipboard = screenshots(paths[0]) if len(paths) == 1 else paths
    stock, custom = (Screen(path).measurements() for path in (native, clipboard))
    for key, expected in stock.items():
        actual = custom[key]
        print(f"{key}: iOS {expected}, Clipboard {actual}", flush=True)
        tolerance = 4 if key.endswith(" bounds") else 5
        if any(abs(a - b) > tolerance for a, b in zip(expected, actual)):
            raise SystemExit(f"{key} differs by more than {tolerance}")
