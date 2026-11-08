#!/usr/bin/env python3
"""VIS-01: quantitative per-pixel report against exact owner reference PNGs.

Run locally (not a default green CI gate; the original owner archive must
be provided explicitly):
  python -m pip install Pillow
  python tools/compare_visual_reference.py \\
     --pack my_shelter_visual_reference_pack_v1.zip \\
     --captures /tmp/shelter-visual \\
     --output visual-diff-report

No image is generated, stretched, edited or silently substituted for a
reference. No numeric PASS without an owner-selected acceptance threshold.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
from zipfile import ZipFile

try:
    from PIL import Image, ImageChops, ImageEnhance
except ImportError as exc:
    raise SystemExit("VISUAL REFERENCE: NOT_RUN — install Pillow first") from exc

REGIONS = {
    "title": (16, 8, 420, 43),
    "status": (14, 47, 666, 150),
    "quest": (14, 157, 342, 310),
    "minimap": (1433, 17, 1640, 204),
    "hotbar": (15, 782, 350, 872),
    "footer": (0, 873, 1672, 941),
    "center_location": (400, 7, 735, 51),
}
NAMES = {
    "R1": ("R1_shelter.png", "reference_R1_shelter_1672x941.png"),
    "R2": ("R2_zombie_street.png", "reference_R2_street_1672x941.png"),
    "R3": ("R3_hospital.png", "reference_R3_hospital_1672x941.png"),
    "R4": ("R4_apartment.png", "reference_R4_apartment_1672x941.png"),
}
REFERENCE_SHA256 = {
    "R1": "d70f66c758ebb4fcf137f92ffd190a7dd833c5c1766306ebbe29d2f92ed9ddb3",
    "R2": "8416a6d9c2e4a9fa7bd34dce69dfc6280c0fc15f1b2e48831868675d70d3c327",
    "R3": "a22e12e90e8d3e419d625a07948e31b752bd8eb0175380894b9b6e1bb7a29720",
    "R4": "0a05c39bd74af351737a16b01f514401f10ece6b3001f069574acc2ff7c395bf",
}
EXPECTED_SIZE = (1672, 941)


def metrics(left, right):
    delta = ImageChops.difference(left, right)
    hist = delta.histogram()
    total = float(left.width * left.height * 3)
    mae = sum(value * count for channel in range(3)
              for value, count in enumerate(hist[channel * 256:(channel + 1) * 256])) / total
    squared = sum((value ** 2) * count for channel in range(3)
                  for value, count in enumerate(hist[channel * 256:(channel + 1) * 256]))
    return {"mae_rgb": round(mae, 4), "rmse_rgb": round(math.sqrt(squared / total), 4),
            "psnr_db": None if squared == 0 else round(20 * math.log10(255 / math.sqrt(squared / total)), 4),
            "pixel_identical": squared == 0}


def compare_item(pack, rid, original_filename, candidate_filename, output, captures):
    data = pack.read("originals/" + original_filename)
    digest = hashlib.sha256(data).hexdigest()
    if digest != REFERENCE_SHA256[rid]:
        raise ValueError("VISUAL REFERENCE: SHA_MISMATCH " + rid)
    import io
    original = Image.open(io.BytesIO(data)).convert("RGB")
    candidate_path = captures / candidate_filename
    if not candidate_path.is_file():
        return {"status": "NOT_RUN", "reason": "Godot candidate missing", "file": str(candidate_path)}
    candidate = Image.open(candidate_path).convert("RGB")
    if original.size != EXPECTED_SIZE or candidate.size != EXPECTED_SIZE:
        return {"status": "NOT_COMPARABLE", "original_size": original.size,
                "candidate_size": candidate.size, "expected_size": EXPECTED_SIZE}
    diff = ImageChops.difference(original, candidate)
    overlay = Image.blend(original, candidate, 0.5)
    heatmap = ImageEnhance.Contrast(diff).enhance(2.4)
    overlay.save(output / (rid + "_overlay.png"))
    heatmap.save(output / (rid + "_diff.png"))
    result = {"status": "REPORT_ONLY_NOT_ACCEPTED", "reference_sha256": digest,
              "full_frame": metrics(original, candidate), "regions": {}}
    for region, box in REGIONS.items():
        result["regions"][region] = metrics(original.crop(box), candidate.crop(box))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", type=Path, required=True)
    parser.add_argument("--captures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {"status": "REPORT_ONLY_NOT_ACCEPTED", "note":
              "Per-pixel difference does not account for differing seed, character state, artwork assets or time; owner approval is separate.", "references": {}}
    with ZipFile(args.pack) as pack:
        for rid, (original, candidate) in NAMES.items():
            report["references"][rid] = compare_item(pack, rid, original, candidate, args.output, args.captures)
    (args.output / "visual_comparison.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if all(row["status"] == "NOT_RUN" for row in report["references"].values()):
        raise SystemExit("VISUAL REFERENCE: NOT_RUN — no generated Godot candidates to compare")
    print("VISUAL REFERENCE: quantitative REPORT_ONLY; NOT A PIXEL-ACCURACY PASS")


if __name__ == "__main__":
    main()
