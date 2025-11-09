#!/usr/bin/env python3
"""
Gemini Room Design Generator
(Updated: generates furniture search terms instead of full JSON plans)

Workflow:
1. Extract room info from USDZ
2. Ask Gemini to generate thematic furniture search terms
3. Output JSON of search terms (no product links, images, or scraping)
"""

import os
import sys
import json
import argparse
import time
import zipfile
import tempfile
import shutil
import re
from pathlib import Path
import google.generativeai as genai
from typing import List, Dict, Any


# -------------------------------------------------------
# Gemini Setup
# -------------------------------------------------------
def setup_gemini(api_key: str = None):
    """Configure Gemini API"""
    if api_key is None:
        api_key = os.environ.get("GEMINI_API_KEY")

    if not api_key:
        raise ValueError("GEMINI_API_KEY not provided. Set via environment variable or pass as argument.")

    genai.configure(api_key=api_key)

    # ✅ No web search tools needed — just plain text generation
    model = genai.GenerativeModel("gemini-2.0-flash-exp")
    return model


# -------------------------------------------------------
# USDZ Utilities
# -------------------------------------------------------
def parse_usd_file(usd_path: Path) -> Dict[str, Any]:
    """Parse USD/USDC file to extract dimensions"""
    try:
        with open(usd_path, "r", errors="ignore") as f:
            content = f.read()

        extent_pattern = r"float3\[\]\s+extent\s*=\s*\[(.*?)\]"
        match = re.search(extent_pattern, content)
        dims = {"width": None, "length": None, "height": None}

        if match:
            vals = [float(x.strip()) for x in match.group(1).replace("(", "").replace(")", "").split(",")]
            if len(vals) == 6:
                dims["width"] = abs(vals[3] - vals[0])
                dims["height"] = abs(vals[4] - vals[1])
                dims["length"] = abs(vals[5] - vals[2])

        print(f"📐 Extracted dimensions: {dims}", file=sys.stderr)
        return dims
    except Exception as e:
        print(f"⚠️  Could not parse USD file: {e}", file=sys.stderr)
        return {"width": None, "length": None, "height": None}


def extract_usdz_info(usdz_path: Path) -> Dict[str, Any]:
    """Extract information from USDZ file"""
    try:
        print(f"📦 Extracting USDZ: {usdz_path.name}", file=sys.stderr)
        tmpdir = Path(tempfile.mkdtemp())
        with zipfile.ZipFile(usdz_path, "r") as zf:
            zf.extractall(tmpdir)
        usd_files = list(tmpdir.rglob("*.usd")) + list(tmpdir.rglob("*.usdc"))

        dims = parse_usd_file(usd_files[0]) if usd_files else None
        return {"dimensions": dims, "temp_dir": tmpdir}
    except Exception as e:
        print(f"❌ Error extracting USDZ: {e}", file=sys.stderr)
        return {"dimensions": None, "temp_dir": None}


# -------------------------------------------------------
# Prompt and Generation
# -------------------------------------------------------
def estimate_room_dimensions(room_type: str) -> Dict[str, float]:
    """Estimate dimensions when unavailable"""
    typical = {
        "bedroom": {"width": 3.5, "length": 4.0, "height": 2.7},
        "living_room": {"width": 4.5, "length": 5.5, "height": 2.7},
        "kitchen": {"width": 3.0, "length": 4.0, "height": 2.7},
        "bathroom": {"width": 2.5, "length": 2.5, "height": 2.7},
        "dining_room": {"width": 3.5, "length": 4.5, "height": 2.7},
        "office": {"width": 3.0, "length": 3.5, "height": 2.7},
    }
    return typical.get(room_type, {"width": 4.0, "length": 4.5, "height": 2.7})


def create_prompt(room_type: str, budget: str, dims: Dict) -> str:
    """Prompt asking Gemini for search terms only"""
    width, length, height = (
        dims.get("width", 4.0),
        dims.get("length", 4.5),
        dims.get("height", 2.7),
    )

    prompt = f"""
You are an expert interior designer.

Your task is to propose furniture concepts for a {room_type} design project
with a total budget of about ${budget}.

ROOM DIMENSIONS:
- {width}m wide × {length}m long × {height}m high

Create **3 different design plans** (Modern, Traditional, Minimalist themes).
Each plan should contain **5–8 furniture or decor search phrases**, describing items
someone might look up online (e.g. "red leather couch", "oak coffee table", "grey patterned rug").

FORMAT REQUIREMENTS:
- Output only valid JSON.
- JSON is a list of lists.
- Each sublist contains plain strings (search phrases).
- Each sublist is a plan

Example:
[
  ["modern grey couch", "glass coffee table", "black floor lamp"],
  ["rustic wooden bed", "vintage nightstand"],
  ["minimalist desk", "ergonomic chair", "white bookshelf"]
]

Return only the JSON.

DO NOT RETURN ANYTHING THAT GOES ON WALLS

ONLY RETURN A MAX OF 2 PIECES PER PLAN

ONLY RETURN ONE PLAN

"""
    return prompt.strip()


def generate_search_terms(model, room_type: str, budget: str, room_info: Dict) -> List[List[str]]:
    """Generate furniture search term lists"""
    try:
        dims = room_info.get("dimensions") or estimate_room_dimensions(room_type)
        prompt = create_prompt(room_type, budget, dims)

        print(f"💭 Sending request to Gemini (generate search terms)...", file=sys.stderr)
        response = model.generate_content(prompt)
        text = response.text.strip()

        if text.startswith("```json"):
            text = text[7:]
        if text.startswith("```"):
            text = text[3:]
        if text.endswith("```"):
            text = text[:-3]
        text = text.strip()

        try:
            plans = json.loads(text)
        except json.JSONDecodeError:
            match = re.search(r"\[[\s\S]*\]", text)
            if match:
                plans = json.loads(match.group(0))
            else:
                raise ValueError("Failed to parse Gemini output as JSON")

        if not isinstance(plans, list):
            raise ValueError("Gemini did not return a list")

        print(f"✅ Generated {len(plans)} design plans", file=sys.stderr)
        return plans

    except Exception as e:
        print(f"❌ Error generating search terms: {e}", file=sys.stderr)
        raise


# -------------------------------------------------------
# Main Entrypoint
# -------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Generate furniture search term plans using Gemini")
    parser.add_argument("--room", required=True, help="Path to room scan USDZ file")
    parser.add_argument("--budget", required=True, help="Budget in dollars")
    parser.add_argument("--type", required=True, help="Room type (bedroom, kitchen, etc)")
    parser.add_argument("--api-key", help="Gemini API key (optional)")
    args = parser.parse_args()

    room_path = Path(args.room)
    if not room_path.exists():
        print(f"❌ Room scan file not found: {args.room}", file=sys.stderr)
        sys.exit(1)

    temp_dir = None
    try:
        model = setup_gemini(args.api_key)
        info = extract_usdz_info(room_path)
        temp_dir = info.get("temp_dir")

        search_plans = generate_search_terms(model, args.type, args.budget, info)
        print(json.dumps(search_plans, indent=2))

    except Exception as e:
        print(f"❌ Fatal error: {e}", file=sys.stderr)
        import traceback; traceback.print_exc(file=sys.stderr)
        sys.exit(1)
    finally:
        if temp_dir and Path(temp_dir).exists():
            shutil.rmtree(temp_dir, ignore_errors=True)
            print("🧹 Cleaned up temporary files", file=sys.stderr)


if __name__ == "__main__":
    main()

