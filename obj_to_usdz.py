#!/usr/bin/env python3
"""
Custom OBJ to USDZ converter that preserves vertex colors.
Handles non-standard OBJ format with RGB values appended to vertex positions.

Usage:
    python obj_to_usdz.py input.obj output.usdz
    
Requirements:
    pip install usd-core
"""

import sys
import os
import re
from pathlib import Path

try:
    from pxr import Usd, UsdGeom, Vt, Gf, Sdf
except ImportError:
    print("Error: USD Python bindings not found.")
    print("Install with: pip install usd-core")
    sys.exit(1)


def parse_obj_with_colors(obj_path):
    """
    Parse OBJ file with vertex colors in format:
    v x y z r g b
    
    Returns:
        vertices: list of (x, y, z) tuples
        colors: list of (r, g, b) tuples (0-1 range)
        faces: list of face indices (0-based)
    """
    vertices = []
    colors = []
    faces = []
    
    vertex_count = 0
    with open(obj_path, 'r') as f:
        for line in f:
            line = line.strip()
            
            # Skip comments and empty lines
            if not line or line.startswith('#'):
                continue
            
            parts = line.split()
            if not parts:
                continue
            
            # Parse vertex with color
            if parts[0] == 'v':
                vertex_count += 1
                if len(parts) >= 7:  # v x y z r g b
                    x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
                    r, g, b = float(parts[4]), float(parts[5]), float(parts[6])
                    vertices.append((x, y, z))
                    colors.append((r, g, b))
                    
                    # Debug: print first 3 vertices
                    if vertex_count <= 3:
                        print(f"DEBUG Vertex {vertex_count}: pos=({x:.3f}, {y:.3f}, {z:.3f}), color=({r:.3f}, {g:.3f}, {b:.3f})")
                        
                elif len(parts) >= 4:  # v x y z (no color)
                    x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
                    vertices.append((x, y, z))
                    colors.append((1.0, 1.0, 1.0))  # Default white
                    if vertex_count <= 3:
                        print(f"DEBUG Vertex {vertex_count}: NO COLOR - using white")
            
            # Parse face (convert to 0-based indexing)
            elif parts[0] == 'f':
                face_indices = []
                for vertex_data in parts[1:]:
                    # Handle f v, f v/vt, f v/vt/vn, f v//vn formats
                    vertex_idx = int(vertex_data.split('/')[0])
                    # OBJ uses 1-based indexing, convert to 0-based
                    face_indices.append(vertex_idx - 1)
                
                # Triangulate if needed (assuming convex polygons)
                if len(face_indices) == 3:
                    faces.append(face_indices)
                elif len(face_indices) > 3:
                    # Simple fan triangulation
                    for i in range(1, len(face_indices) - 1):
                        faces.append([face_indices[0], face_indices[i], face_indices[i + 1]])
    
    return vertices, colors, faces


def create_usdz(vertices, colors, faces, output_path):
    """
    Create USDZ file with mesh and vertex colors.
    """
    # Determine intermediate file format
    if output_path.endswith('.usdz'):
        # Create intermediate USDC file
        intermediate_path = output_path.replace('.usdz', '.usdc')
    else:
        intermediate_path = output_path
    
    # Create USD stage
    stage = Usd.Stage.CreateNew(intermediate_path)
    
    # Set up for USDZ export
    stage.SetDefaultPrim(stage.DefinePrim('/World'))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    
    # Create mesh
    mesh_path = '/World/Mesh'
    mesh = UsdGeom.Mesh.Define(stage, mesh_path)
    
    # Set vertices
    points = Vt.Vec3fArray([Gf.Vec3f(v[0], v[1], v[2]) for v in vertices])
    mesh.GetPointsAttr().Set(points)
    
    # Set face vertex counts (all triangles = 3)
    face_vertex_counts = Vt.IntArray([len(face) for face in faces])
    mesh.GetFaceVertexCountsAttr().Set(face_vertex_counts)
    
    # Set face vertex indices (flatten the faces list)
    face_vertex_indices = Vt.IntArray([idx for face in faces for idx in face])
    mesh.GetFaceVertexIndicesAttr().Set(face_vertex_indices)
    
    # Set vertex colors - use displayColor primvar only (most compatible)
    color_primvar = mesh.CreateDisplayColorPrimvar(UsdGeom.Tokens.vertex)
    color_array = Vt.Vec3fArray([Gf.Vec3f(c[0], c[1], c[2]) for c in colors])
    color_primvar.Set(color_array)
    
    # Explicitly set interpolation to vertex
    color_primvar.SetInterpolation(UsdGeom.Tokens.vertex)
    
    # Set displayOpacity for completeness
    opacity_primvar = mesh.CreateDisplayOpacityPrimvar(UsdGeom.Tokens.vertex)
    opacity_array = Vt.FloatArray([1.0] * len(colors))
    opacity_primvar.Set(opacity_array)
    opacity_primvar.SetInterpolation(UsdGeom.Tokens.vertex)
    
    # Save the stage
    stage.GetRootLayer().Save()
    print(f"Created USD file: {intermediate_path}")
    
    # Convert to USDZ if output has .usdz extension
    if output_path.endswith('.usdz'):
        # Create USDZ using Python's zipfile (USDZ is just a ZIP with no compression)
        try:
            import zipfile
            with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_STORED) as zipf:
                # Add the USDC file to the root of the archive
                arcname = os.path.basename(intermediate_path)
                zipf.write(intermediate_path, arcname)
            
            print(f"Created USDZ file: {output_path}")
            
            # Clean up temporary usdc file
            if os.path.exists(intermediate_path):
                os.remove(intermediate_path)
                
        except Exception as e:
            print(f"Warning: Failed to create USDZ: {e}")
            print(f"Saved as USDC instead: {intermediate_path}")


def main():
    if len(sys.argv) != 3:
        print("Usage: python obj_to_usdz.py input.obj output.usdz")
        sys.exit(1)
    
    input_path = sys.argv[1]
    output_path = sys.argv[2]
    
    if not os.path.exists(input_path):
        print(f"Error: Input file not found: {input_path}")
        sys.exit(1)
    
    print(f"Reading OBJ file: {input_path}")
    vertices, colors, faces = parse_obj_with_colors(input_path)
    
    print(f"Parsed {len(vertices)} vertices, {len(colors)} colors, {len(faces)} faces")
    
    if len(vertices) == 0:
        print("Error: No vertices found in OBJ file")
        sys.exit(1)
    
    if len(colors) != len(vertices):
        print(f"Warning: Color count ({len(colors)}) doesn't match vertex count ({len(vertices)})")
    
    print(f"Creating USDZ file: {output_path}")
    create_usdz(vertices, colors, faces, output_path)
    
    print("Conversion complete!")


if __name__ == "__main__":
    main()
