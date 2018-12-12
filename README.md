Godot Terrain Plugin
======================

This is a heightmap-based terrain node for Godot Engine 2.1, written in GDScript.

![Editor screenshot](http://zylannprods.fr/lab/godot/terrain_plugin/TerrainEditor_screen4.png)

Important
-----------
I ported this plugin to Godot 3: https://github.com/Zylann/godot_heightmap_plugin  
I used to also work on a module version: https://github.com/Zylann/godot_heightmap_module  
I stopped support on Godot 2.

Features
----------

- Custom Terrain node
- Resizeable square between 1 and 1024 units of space
- Raise, carve and smooth the terrain in the editor
- Paint vertex colors to add textures with shaders 
- Brush with customizable shape, size and opacity
- Takes advantage of frustum culling by chunking the terrain in multiple meshes
- Collisions
- Smooth or hard-edges rendering
- Save to image and normal map
- Terrain data saved inside the scene like Tilemap and Gridmap
- Edition behaviour works both in editor and game
- Undo/redo
- Experimental: quad rotation to improve shading in some cases

- Extras: sample assets in this repo :)


TODO/ideas
-----------

- Meshing is very slow (will this plugin remain pure GDScript?)
- Level of detail (non-trivial! Requires faster meshing)
- Baked mode for faster terrain loading (it is currently rebuilt from data both in editor and game)
- Save terrain data as a separate resource to unbloat the scene file
- Decorrelate resolution and size
- Make Terrain inherit Spatial so it can be moved around
- Paint meshes on top of the terrain (grass, trees, rocks...) <-- I want to make a vegetation generator plugin too :p
- Improve normals (data "pixels" produce lighting artefacts)
- Make live edition work
- Mesh simplification (an editor lib would be welcome)
- Infinite terrain mode

- Extras: importer for terrains made in DCCs (Blender/3DS etc)

