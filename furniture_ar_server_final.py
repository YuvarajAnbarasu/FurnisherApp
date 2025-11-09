#!/usr/bin/env python3
"""
Furniture AR Server Handler with Complete Pipeline
1. Scrape images from Google
2. Download images to organized directory
3. Run InstantMesh to generate 3D models
4. Convert OBJ to USDZ
5. Return USDZ files with placement info
"""

from flask import Flask, request, jsonify, send_file
from werkzeug.utils import secure_filename
import os
import json
import uuid
import subprocess
import requests
from pathlib import Path
import shutil
from typing import List, Dict, Any, Optional
import traceback

app = Flask(__name__)

# Configuration
BASE_DIR = Path("/home/zliu989/Server")
SCANS_DIR = BASE_DIR / "scans"
USDZ_OUTPUTS_DIR = BASE_DIR / "usdz_outputs"
INSTANTMESH_DIR = Path("/home/zliu989/InstantMesh")
INSTANTMESH_OUTPUT_DIR = INSTANTMESH_DIR / "outputs/instant-mesh-large/meshes"
SCRAPER_SCRIPT = BASE_DIR / "scraper.py"
OBJ_TO_USDZ_SCRIPT = BASE_DIR / "obj_to_usdz.py"

for d in [SCANS_DIR, USDZ_OUTPUTS_DIR]:
    d.mkdir(parents=True, exist_ok=True)

ALLOWED_EXTENSIONS = {"usdz", "usdc"}


def allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


def run_gemini_model(room_scan_path: str, budget: str, room_type: str) -> List[List]:
    """Run Gemini model to generate search term plans"""
    try:
        cmd = [
            "python3", "gemscript.py",
            "--room", room_scan_path,
            "--budget", budget,
            "--type", room_type
        ]
        print(f"🤖 Running Gemini model: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=BASE_DIR)

        if result.returncode != 0:
            print(f"❌ Gemini model error: {result.stderr}")
            raise Exception(f"Gemini model failed: {result.stderr}")

        plans = json.loads(result.stdout)
        print(f"✅ Gemini returned {len(plans)} plans with {sum(len(p) for p in plans)} total items")
        return plans
    except Exception as e:
        print(f"❌ Gemini model error: {e}")
        raise


def run_image_scraper(search_terms: List[str]) -> List[Dict]:
    """Run image scraper to get furniture images"""
    try:
        print(f"🔍 Running image scraper for {len(search_terms)} items...")
        
        cmd = [
            "python3", str(SCRAPER_SCRIPT),
            "--terms", json.dumps(search_terms)
        ]
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd=BASE_DIR,
            timeout=300
        )
        
        if result.returncode != 0:
            print(f"⚠️ Scraper error: {result.stderr}")
            raise Exception(f"Scraper failed: {result.stderr}")
        
        products = json.loads(result.stdout)
        print(f"✅ Scraper returned {len(products)} products")
        return products
        
    except Exception as e:
        print(f"❌ Scraper error: {e}")
        traceback.print_exc()
        raise


def download_image(image_url: str, save_path: Path) -> bool:
    """Download an image from URL and save it"""
    try:
        print(f"  📥 Downloading: {image_url[:60]}...", file=sys.stderr)
        
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }
        
        response = requests.get(image_url, headers=headers, timeout=30, stream=True)
        response.raise_for_status()
        
        # Save the image
        with open(save_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        print(f"  ✅ Saved to: {save_path.name}")
        return True
        
    except Exception as e:
        print(f"  ❌ Failed to download image: {e}")
        return False


def run_instantmesh(images_dir: Path) -> Dict[str, Path]:
    """
    Run InstantMesh on all images in directory
    Returns dict mapping image_name -> obj_path
    """
    try:
        print(f"\n{'🔷'*30}")
        print(f"Running InstantMesh on: {images_dir}")
        print(f"{'🔷'*30}\n")
        
        cmd = [
            "python", 
            str(INSTANTMESH_DIR / "run.py"),
            "configs/instant-mesh-large.yaml",
            str(images_dir)
        ]
        
        print(f"Command: {' '.join(cmd)}")
        
        result = subprocess.run(
            cmd,
            cwd=INSTANTMESH_DIR,
            capture_output=True,
            text=True,
            timeout=600  # 10 minutes
        )
        
        if result.returncode != 0:
            print(f"⚠️ InstantMesh stderr: {result.stderr}")
            # Don't raise - InstantMesh might still have created some files
        
        print(f"InstantMesh stdout:\n{result.stdout}")
        
        # Find generated OBJ files
        obj_files = {}
        if INSTANTMESH_OUTPUT_DIR.exists():
            for obj_file in INSTANTMESH_OUTPUT_DIR.glob("*.obj"):
                # Extract original image name (without extension)
                image_name = obj_file.stem
                obj_files[image_name] = obj_file
                print(f"✅ Found OBJ: {obj_file.name}")
        
        print(f"\n✅ InstantMesh generated {len(obj_files)} OBJ files")
        return obj_files
        
    except subprocess.TimeoutExpired:
        print(f"❌ InstantMesh timed out after 10 minutes")
        raise
    except Exception as e:
        print(f"❌ InstantMesh error: {e}")
        traceback.print_exc()
        raise


def convert_obj_to_usdz(obj_path: Path, usdz_path: Path) -> bool:
    """Convert OBJ file to USDZ"""
    try:
        print(f"  🔄 Converting {obj_path.name} to USDZ...")
        
        # Ensure output directory exists
        usdz_path.parent.mkdir(parents=True, exist_ok=True)
        
        cmd = [
            "python3",
            str(OBJ_TO_USDZ_SCRIPT),
            str(obj_path),
            str(usdz_path)
        ]
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd=BASE_DIR,
            timeout=60
        )
        
        if result.returncode != 0:
            print(f"  ❌ Conversion failed: {result.stderr}")
            return False
        
        if usdz_path.exists():
            print(f"  ✅ Created: {usdz_path.name}")
            return True
        else:
            print(f"  ❌ USDZ file not created")
            return False
            
    except Exception as e:
        print(f"  ❌ Conversion error: {e}")
        return False


@app.route("/generate-design", methods=["POST"])
def generate_design():
    """Main endpoint - complete pipeline from room scan to USDZ files"""
    try:
        if "file" not in request.files:
            return jsonify({"error": "No file provided"}), 400

        file = request.files["file"]
        if file.filename == "" or not allowed_file(file.filename):
            return jsonify({"error": "Invalid file"}), 400

        room_type = request.form.get("room_type", "bedroom")
        budget = request.form.get("budget", "5000")

        print(f"\n{'='*60}")
        print(f"📥 New request: room_type={room_type}, budget=${budget}")
        print(f"{'='*60}\n")

        # Create unique scan ID and directory structure
        scan_id = str(uuid.uuid4())
        scan_dir = SCANS_DIR / scan_id
        scan_dir.mkdir(parents=True, exist_ok=True)

        # Save uploaded room scan
        filename = secure_filename(file.filename)
        scan_path = scan_dir / filename
        file.save(scan_path)
        print(f"💾 Saved room scan: {scan_path}")

        # Step 1: Run Gemini to get furniture search terms
        try:
            furniture_plans = run_gemini_model(str(scan_path), budget, room_type)
        except Exception as e:
            return jsonify({"error": f"Gemini model failed: {e}", "scan_id": scan_id}), 500

        # Step 2: Flatten all search terms and run image scraper
        all_search_terms = []
        for plan in furniture_plans:
            for item in plan:
                search_term = item if isinstance(item, str) else item.get("name", "furniture")
                all_search_terms.append(search_term)
        
        print(f"\n{'🔍'*30}")
        print(f"Scraping images for {len(all_search_terms)} furniture items")
        print(f"{'🔍'*30}\n")
        
        try:
            scraped_products = run_image_scraper(all_search_terms)
        except Exception as e:
            return jsonify({"error": f"Image scraper failed: {e}", "scan_id": scan_id}), 500

        # Step 3: Process each plan
        response_plans = []
        product_idx = 0
        
        for plan_idx, plan in enumerate(furniture_plans):
            plan_id = f"plan_{plan_idx}"
            print(f"\n{'─'*60}")
            print(f"Processing {plan_id} with {len(plan)} furniture items")
            print(f"{'─'*60}")

            # Create directories for this plan
            plan_images_dir = scan_dir / plan_id / "images"
            plan_images_dir.mkdir(parents=True, exist_ok=True)
            
            plan_usdz_dir = USDZ_OUTPUTS_DIR / scan_id / plan_id
            plan_usdz_dir.mkdir(parents=True, exist_ok=True)

            # Step 4: Download images for this plan
            image_map = {}  # Maps furniture_id to image filename
            
            for item_idx in range(len(plan)):
                if product_idx >= len(scraped_products):
                    break
                
                product = scraped_products[product_idx]
                furniture_id = f"furniture_{item_idx}"
                
                print(f"\n  📦 {furniture_id}: {product.get('title', 'Unknown')}")
                
                if product.get('image'):
                    # Determine image extension
                    image_url = product['image']
                    ext = 'jpg'
                    if '.png' in image_url:
                        ext = 'png'
                    elif '.webp' in image_url:
                        ext = 'webp'
                    
                    # Save with structured name: plan_X_furniture_Y.ext
                    image_filename = f"{plan_id}_{furniture_id}.{ext}"
                    image_path = plan_images_dir / image_filename
                    
                    if download_image(image_url, image_path):
                        image_map[furniture_id] = image_filename
                    else:
                        print(f"  ⚠️ Failed to download image for {furniture_id}")
                else:
                    print(f"  ⚠️ No image URL for {furniture_id}")
                
                product_idx += 1
            
            # Step 5: Run InstantMesh on all images for this plan
            if image_map:
                print(f"\n{'🎨'*30}")
                print(f"Running InstantMesh for {plan_id}")
                print(f"{'🎨'*30}\n")
                
                try:
                    obj_files = run_instantmesh(plan_images_dir)
                except Exception as e:
                    print(f"❌ InstantMesh failed for {plan_id}: {e}")
                    obj_files = {}
                
                # Step 6: Convert OBJ files to USDZ
                plan_furniture = []
                
                for furniture_id, image_filename in image_map.items():
                    image_stem = Path(image_filename).stem  # e.g., "plan_0_furniture_1"
                    
                    furniture_item = {
                        "furniture_id": furniture_id,
                        "name": furniture_id.replace('_', ' ').title(),
                        "status": "pending",
                        "usdz_url": "",
                        "position": {"x": 0, "y": 0, "z": 0}
                    }
                    
                    if image_stem in obj_files:
                        obj_path = obj_files[image_stem]
                        usdz_filename = f"{image_stem}.usdz"
                        usdz_path = plan_usdz_dir / usdz_filename
                        
                        if convert_obj_to_usdz(obj_path, usdz_path):
                            furniture_item["status"] = "ready"
                            furniture_item["usdz_url"] = f"/download/{scan_id}/{plan_id}/{usdz_filename}"
                        else:
                            furniture_item["status"] = "conversion_failed"
                    else:
                        furniture_item["status"] = "3d_generation_failed"
                    
                    plan_furniture.append(furniture_item)
                
                response_plans.append({
                    "plan_id": plan_id,
                    "furniture": plan_furniture,
                    "total_items": len(plan_furniture),
                    "ready_items": len([f for f in plan_furniture if f["status"] == "ready"])
                })

        response = {
            "scan_id": scan_id,
            "room_scan_url": f"/download/{scan_id}/{filename}",
            "plans": response_plans,
            "total_plans": len(response_plans),
            "pipeline_complete": True
        }

        print(f"\n{'='*60}")
        print(f"✅ Processing complete!")
        print(f"   Plans: {len(response_plans)}")
        print(f"   Total furniture: {sum(p['total_items'] for p in response_plans)}")
        print(f"   Ready for AR: {sum(p['ready_items'] for p in response_plans)}")
        print(f"{'='*60}\n")
        
        return jsonify(response), 200

    except Exception as e:
        print(f"\n❌ Error in generate_design: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/download/<scan_id>/<path:filepath>", methods=["GET"])
def download_file(scan_id, filepath):
    """Download USDZ or room scan file"""
    try:
        # Try USDZ outputs first
        usdz_path = USDZ_OUTPUTS_DIR / scan_id / filepath
        if usdz_path.exists():
            return send_file(usdz_path, mimetype="application/octet-stream")
        
        # Try scans directory
        scan_path = SCANS_DIR / scan_id / filepath
        if scan_path.exists():
            return send_file(scan_path, mimetype="application/octet-stream")
        
        return jsonify({"error": "File not found"}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/scan/<scan_id>", methods=["GET"])
def get_scan_info(scan_id):
    """Get information about a specific scan"""
    try:
        scan_dir = SCANS_DIR / scan_id
        if not scan_dir.exists():
            return jsonify({"error": "Scan not found"}), 404

        plans = []
        usdz_dir = USDZ_OUTPUTS_DIR / scan_id
        if usdz_dir.exists():
            for plan_dir in sorted(usdz_dir.iterdir()):
                if plan_dir.is_dir():
                    usdz_files = list(plan_dir.glob("*.usdz"))
                    plans.append({
                        "plan_id": plan_dir.name,
                        "furniture_count": len(usdz_files),
                        "files": [f.name for f in usdz_files]
                    })
        
        return jsonify({"scan_id": scan_id, "plans": plans}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/cleanup/<scan_id>", methods=["DELETE"])
def cleanup_scan(scan_id):
    """Clean up files for a specific scan"""
    try:
        removed = []
        for d in [SCANS_DIR / scan_id, USDZ_OUTPUTS_DIR / scan_id]:
            if d.exists():
                shutil.rmtree(d)
                removed.append(str(d))
        return jsonify({"message": "Cleanup successful", "deleted": removed}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "scraper_available": SCRAPER_SCRIPT.exists(),
        "instantmesh_available": INSTANTMESH_DIR.exists(),
        "obj_to_usdz_available": OBJ_TO_USDZ_SCRIPT.exists()
    }), 200


if __name__ == "__main__":
    import sys
    
    print("\n" + "="*60)
    print("🚀 Furniture AR Server Starting (Full Pipeline)...")
    print("="*60)
    print(f"Base directory: {BASE_DIR}")
    print(f"Scans directory: {SCANS_DIR}")
    print(f"USDZ outputs: {USDZ_OUTPUTS_DIR}")
    print(f"InstantMesh: {INSTANTMESH_DIR}")
    print(f"Scraper: {SCRAPER_SCRIPT}")
    print(f"OBJ to USDZ: {OBJ_TO_USDZ_SCRIPT}")
    print("="*60 + "\n")

    app.run(host="0.0.0.0", port=5000, debug=True)