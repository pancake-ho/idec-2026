#!/usr/bin/env python3
"""Extract an exactly matching decoded frame across local BBB DASH AVC representations.

Run from adv_theme:
    python dash_img/extract_bbb.py --list
    python dash_img/extract_bbb.py --time 120.5

This helper never downloads media, interpolates frames, or treats MPD bandwidth as SSIM.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
import xml.etree.ElementTree as ET

try:
    from PIL import Image, ImageDraw, ImageFont, ImageOps
except ImportError as exc:
    raise SystemExit("Pillow is required: python -m pip install Pillow") from exc

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_TARGETS = [131087, 595491, 3078587]  # Exact MPD bandwidth, bps, not measured per-frame bitrate.


@dataclass(frozen=True)
class Rep:
    idx: int
    rep_id: str
    bandwidth: int
    width: int
    height: int
    fps: Fraction
    path: Path


def call(cmd: list[str]) -> str:
    done = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if done.returncode:
        raise RuntimeError(f"Command failed ({done.returncode}): {' '.join(map(str, cmd))}\n{done.stderr[-4000:]}")
    return done.stdout


def parse_catalog(mpd: Path, local_dir: Path) -> list[Rep]:
    root = ET.parse(mpd).getroot()
    if root.get("type") != "static" or "on-demand" not in root.get("profiles", ""):
        raise ValueError("Expected a static on-demand MPD, not a different streaming dataset")
    ns_match = re.match(r"\{(.+?)\}", root.tag)
    ns = {"m": ns_match.group(1)} if ns_match else {"m": ""}
    def tag(name: str) -> str:
        return f"{{{ns['m']}}}{name}" if ns["m"] else name
    rows = []
    for period in root.findall(tag("Period")):
        for adaptation in period.findall(tag("AdaptationSet")):
            for rep in adaptation.findall(tag("Representation")):
                codec = rep.get("codecs", adaptation.get("codecs", ""))
                if not codec.startswith(("avc1", "avc3")):
                    continue
                frame_rate = rep.get("frameRate", adaptation.get("frameRate", "24"))
                fps = Fraction(frame_rate.replace(":", "/"))
                rows.append((int(rep.attrib["bandwidth"]), rep.get("id", ""),
                             int(rep.get("width", adaptation.get("width", "0"))),
                             int(rep.get("height", adaptation.get("height", "0"))), fps))
    rows.sort(key=lambda x: x[0])
    if not rows or any(w <= 0 or h <= 0 for _, _, w, h, _ in rows):
        raise ValueError("MPD has no valid AVC video representations")
    if len({x[0] for x in rows}) != len(rows):
        raise ValueError("Duplicated MPD bandwidths: select by representation id instead")
    return [Rep(i, rid, bw, w, h, fps, local_dir / f"rep_{i:02d}.mp4")
            for i, (bw, rid, w, h, fps) in enumerate(rows)]


def file_status(rep: Rep, require_receipt: bool = True) -> str:
    p = rep.path
    if not p.is_file():
        return "MISSING" + (" (.part in progress)" if Path(str(p) + ".part").exists() else "")
    if p.stat().st_size < 4096:
        return "INCOMPLETE (<4 KiB)"
    receipt = Path(str(p) + ".receipt.json")
    if receipt.exists():
        try:
            j = json.loads(receipt.read_text(encoding="utf-8"))
            if int(j["size_bytes"]) != p.stat().st_size:
                return "INCOMPLETE (receipt size mismatch)"
            return "READY"
        except (KeyError, ValueError, json.JSONDecodeError, OSError):
            return "INVALID RECEIPT"
    return "NO RECEIPT" if require_receipt else "READY (no receipt)"


def parse_targets(raw: str) -> list[int]:
    values = [int(x.strip()) for x in raw.split(",")]
    if len(values) != 3 or len(set(values)) != 3 or any(x <= 0 for x in values):
        raise ValueError("--targets requires exactly three unique positive MPD bandwidths")
    if values != sorted(values):
        raise ValueError("--targets must increase: low, medium, high")
    return values


def choose(catalog: list[Rep], targets: list[int], strategy: str, require_receipt: bool) -> list[Rep]:
    by_bw = {r.bandwidth: r for r in catalog}
    ready = [r for r in catalog if file_status(r, require_receipt).startswith("READY")]
    if strategy == "exact":
        selected = []
        for bw in targets:
            if bw not in by_bw:
                raise ValueError(f"Target {bw} bps not present in MPD")
            rep = by_bw[bw]
            status = file_status(rep, require_receipt)
            if not status.startswith("READY"):
                raise ValueError(f"Target {bw} bps: {rep.path} -> {status}. "
                                 "Wait for download or explicitly use --strategy nearest")
            selected.append(rep)
        return selected
    if len(ready) < 3:
        raise ValueError("Need >=3 fully downloaded representations; run --list")
    # Search ordered triples with lexicographically increasing bandwidth;
    # optimize sum squared log2-ratios to each target. Never reuse a rep.
    import itertools
    import math
    selected = min(itertools.combinations(ready, 3),
                   key=lambda combo: sum((math.log2(r.bandwidth / bw)) ** 2
                                         for r, bw in zip(combo, targets)))
    return list(selected)


def ffprobe_video(path: Path) -> dict:
    obj = json.loads(call(["ffprobe", "-v", "error", "-select_streams", "v:0",
                           "-show_streams", "-of", "json", str(path)]))
    streams = obj.get("streams", [])
    if len(streams) != 1:
        raise ValueError(f"Expected one video stream in {path}; got {len(streams)}")
    s = streams[0]
    if s.get("codec_name") != "h264":
        raise ValueError(f"Non-H.264 source: {path}")
    avg = Fraction(s["avg_frame_rate"])
    nominal = Fraction(s["r_frame_rate"])
    if avg <= 0 or nominal != avg:
        raise ValueError(f"Variable/mismatched framerate in {path}")
    start = float(s.get("start_time", "0") or "0")
    if abs(start) > 1e-3:
        raise ValueError(f"Nonzero stream start time ({start}s): cannot assert exact alignment")
    return {"width": int(s["width"]), "height": int(s["height"]),
            "fps": avg, "frames": int(s.get("nb_frames") or 0),
            "duration_sec": float(s.get("duration") or 0),
            "pix_fmt": s.get("pix_fmt", "unknown"), "start_time_sec": start}


def frame_sync_flag() -> list[str]:
    h = call(["ffmpeg", "-hide_banner", "-h", "full"])
    if re.search(r"(?m)^\s*-fps_mode(?:\s|:)", h):
        return ["-fps_mode", "passthrough"]
    if re.search(r"(?m)^\s*-vsync(?:\s|:)", h):
        return ["-vsync", "0"]
    raise RuntimeError("ffmpeg has no frame-passthrough option")


def extract_one(rep: Rep, frame_index: int, destination: Path, sync: list[str]):
    # select=eq(n,...) uses *decoded-frame ordinal*, not keyframe or a nearest timestamp.
    # It forces decoding all frames up to the chosen exact index. This is intentional.
    if destination.exists():
        destination.unlink()  # only our generated output path, never any source video
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(rep.path),
           "-map", "0:v:0", "-an", "-sn", "-dn",
           "-vf", f"select=eq(n\\,{frame_index})", *sync,
           "-frames:v", "1", str(destination)]
    call(cmd)
    if not destination.is_file() or destination.stat().st_size < 100:
        raise RuntimeError(f"Failed to extract decoded frame {frame_index} from {rep.path}")
    with Image.open(destination) as im:
        if im.size != (rep.width, rep.height):
            raise ValueError(f"Extracted image dims {im.size}, expected {(rep.width, rep.height)}")


def font(size: int, bold: bool = False):
    paths = (["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf"] if bold else
             ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
              "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf"])
    for path in paths:
        if Path(path).is_file():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def contain_image(im: Image.Image, size: tuple[int, int]) -> Image.Image:
    return ImageOps.contain(im.convert("RGB"), size, method=Image.Resampling.LANCZOS)


def make_composite(reps: list[Rep], frames: list[Path], frame_idx: int,
                   timestamp: float, out: Path, zoom: bool = False,
                   roi: tuple[float, float, float, float] = (0.40, 0.30, 0.22, 0.22)):
    W, H = 2400, 790
    bg = (248, 250, 253)
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)
    d.text((52, 29), "Big Buck Bunny  |  MPEG-DASH", font=font(37, True), fill=(28, 40, 57))
    d.text((52, 89), f"Same decoded frame: #{frame_idx}   |   {timestamp:.3f} s",
           font=font(24), fill=(78, 91, 109))
    labels = ["LOW BITRATE", "MEDIUM BITRATE", "HIGH BITRATE"]
    margin, gap = 52, 25
    card_w = (W - margin * 2 - gap * 2) // 3
    for i, (rep, p) in enumerate(zip(reps, frames)):
        x = margin + i * (card_w + gap)
        y = 149
        d.rounded_rectangle((x, y, x + card_w, 690), radius=17, fill="white", outline=(222, 228, 236), width=2)
        d.text((x + 21, y + 18), labels[i], font=font(28, True), fill=(28, 40, 57))
        kbps = rep.bandwidth / 1000
        d.text((x + 21, y + 59), f"{kbps:,.1f} kbps  |  {rep.width} x {rep.height}",
               font=font(23), fill=(86, 103, 121))
        image_box = (card_w - 42, 401)
        with Image.open(p) as original:
            native = original.convert("RGB")
            if zoom:
                u, v, rw, rh = roi
                crop = (int(native.width * u), int(native.height * v),
                        int(native.width * (u + rw)), int(native.height * (v + rh)))
                native = native.crop(crop)
            scaled = contain_image(native, image_box)
        px = x + (card_w - scaled.width) // 2
        py = y + 104 + (image_box[1] - scaled.height) // 2
        d.rectangle((x + 18, y + 100, x + card_w - 18, y + 505), fill=(16, 23, 34))
        img.paste(scaled, (px, py))
        d.text((x + 22, y + 512), f"MPD rep #{rep.idx:02d}  |  AVC/H.264",
               font=font(20), fill=(100, 111, 125))
    foot = ("Zoomed matching normalized region (no sharpening or re-encoding)." if zoom else
            "Unmodified decoded PNGs are also saved. No synthetic degradation was applied.")
    d.text((52, 722), foot, font=font(20), fill=(82, 96, 114))
    img.save(out, optimize=True)


def validate_roi(raw: str) -> tuple[float, float, float, float]:
    vals = tuple(float(x.strip()) for x in raw.split(","))
    if len(vals) != 4 or not all(0 <= n <= 1 for n in vals):
        raise ValueError("--roi must have x,y,width,height within 0..1")
    x, y, w, h = vals
    if w <= 0 or h <= 0 or x + w > 1 or y + h > 1:
        raise ValueError("--roi outside image")
    return vals


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--media-work", type=Path, default=Path("runs/assets"), help="existing DASH download root")
    parser.add_argument("--time", type=float, default=120.5, help="video presentation timestamp in seconds; 24 fps -> frame 2892")
    parser.add_argument("--targets", type=str, default=",".join(map(str, DEFAULT_TARGETS)),
                        help="three MPD bandwidths (bps), low,medium,high")
    parser.add_argument("--strategy", choices=["exact", "nearest"], default="exact",
                        help="exact targets, or pick nearest complete downloads")
    parser.add_argument("--allow-unreceipted", action="store_true", help="manual source media without receipt; still ffprobe-checked")
    parser.add_argument("--out", type=Path, default=PACKAGE_ROOT / "dash_img" / "output")
    parser.add_argument("--list", action="store_true", help="list all MPD reps and local download status")
    parser.add_argument("--roi", default="0.40,0.30,0.22,0.22", help="normalized zoom region x,y,w,h")
    args = parser.parse_args()
    if args.time < 0:
        parser.error("--time must be nonnegative")
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        parser.error("ffmpeg and ffprobe must be installed on PATH")
    media_work = args.media_work.resolve()
    local_dir = media_work / "media" / "bbb"
    mpd_candidates = [local_dir / "manifest.mpd", PACKAGE_ROOT / "configs" / "BigBuckBunny_2s_onDemand_2014_05_09.mpd"]
    mpd = next((m for m in mpd_candidates if m.is_file()), None)
    if mpd is None:
        parser.error(f"BBB MPD absent. Tried: {mpd_candidates}. Run existing download step first")
    rows = parse_catalog(mpd, local_dir)
    print(f"[MPD] {mpd}")
    print(f"[MEDIA] {local_dir}")
    print("INDEX    BANDWIDTH      RESOLUTION   FPS      STATUS")
    for r in rows:
        print(f"rep_{r.idx:02d}  {r.bandwidth:>10} bps   {r.width:>4}x{r.height:<4}    {str(r.fps):>5}    "
              f"{file_status(r, not args.allow_unreceipted)}")
    if args.list:
        return 0
    targets = parse_targets(args.targets)
    chosen = choose(rows, targets, args.strategy, not args.allow_unreceipted)
    fps0 = chosen[0].fps
    if any(r.fps != fps0 for r in chosen):
        raise ValueError("Different FPS across chosen reps; matching ordinal is not safe")
    if abs(float(fps0) - 24) > 1e-6:
        raise ValueError(f"Unexpected FPS {fps0}; package expected BBB 24 fps")
    frame_index = int(Fraction(str(args.time)) * fps0 + Fraction(1, 2))  # nearest, half up
    aligned_t = float(Fraction(frame_index) / fps0)
    print(f"[MATCH] Requested {args.time:.3f}s -> exactly decoded frame #{frame_index} ({aligned_t:.6f}s)")
    for label, r in zip(["LOW", "MEDIUM", "HIGH"], chosen):
        print(f"  {label:<7} rep_{r.idx:02d}: {r.bandwidth} bps, {r.width}x{r.height} -> {r.path}")
        p = ffprobe_video(r.path)
        if (p["width"], p["height"], p["fps"]) != (r.width, r.height, r.fps):
            raise ValueError(f"FFprobe vs MPD mismatch: {r.path} -> {p}")
        if p["frames"] and frame_index >= p["frames"]:
            raise ValueError(f"Frame {frame_index} is beyond file frame count {p['frames']}")
        if p["duration_sec"] and aligned_t >= p["duration_sec"]:
            raise ValueError(f"Frame time beyond file duration: {r.path}")
    roi = validate_roi(args.roi)
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    sync = frame_sync_flag()
    suffix = f"t{args.time:.3f}s_f{frame_index:06d}".replace(".", "p")
    frames = []
    result = []
    for level, r in zip(["low", "medium", "high"], chosen):
        path = out / f"bbb_{level}_{suffix}.png"
        print("[DECODE]", path.name, flush=True)
        extract_one(r, frame_index, path, sync)
        frames.append(path)
        result.append({"level": level, "representation_index": r.idx,
                       "mpd_bandwidth_bps": r.bandwidth, "resolution": [r.width, r.height],
                       "fps": str(r.fps), "source": str(r.path), "frame_png": str(path)})
    full = out / f"bbb_comparison_{suffix}.png"
    zoom = out / f"bbb_comparison_zoom_{suffix}.png"
    make_composite(chosen, frames, frame_index, aligned_t, full)
    make_composite(chosen, frames, frame_index, aligned_t, zoom, zoom=True, roi=roi)
    meta = {"video": "Big Buck Bunny", "source_mpd": str(mpd), "requested_time_s": args.time,
            "aligned_time_s": aligned_t, "decoded_frame_index_zero_based": frame_index,
            "selection": args.strategy, "target_mpd_bandwidths_bps": targets,
            "actual_representation_files_checked": True, "quality_measure": "Not measured. MPD bandwidth != SSIM label.",
            "note": "Each image uses the same zero-based decoded frame ordinal, verified H.264/CFR/FPS/start-time.",
            "zoomin_roi_fraction": roi, "representations": result,
            "comparison_png": str(full), "zoom_png": str(zoom)}
    (out / f"bbb_metadata_{suffix}.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    print("[DONE]", full, "\n[DONE]", zoom)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, ET.ParseError) as err:
        print(f"[ERROR] {err}", file=sys.stderr)
        sys.exit(1)
