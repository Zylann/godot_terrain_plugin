tool

# Note:
# This is a very slow part of this plugin, due to GDScript mostly.
# I tried to optimize it without SurfaceTool to reduce calculations,
# but it didn't improve much.
# This plugin must be converted to C++/GDNative.

static func tryget(d, k, defval):
	if d.has(k):
		return d[k]
	return defval

# heights: array of arrays of floats
# normals: arrays of arrays of Vector3
# x0, y0, w, h: sub-rectangle to generate from the above grids
# smooth_shading: if set to true, normals will be used instead of "polygon-looking" ones
# returns: a Mesh
static func make_heightmap(opt):
	# Unpack parameters
	var input_heights = opt.heights
	var input_normals = opt.normals
	var input_colors = opt.colors
	var x0 = opt.x0
	var y0 = opt.y0
	var w = opt.w
	var h = opt.h
	var smooth_shading = tryget(opt, "smooth_shading", true)

	if smooth_shading == false:
		return make_heightmap_faceted(input_heights, input_colors, x0, y0, w, h)
		
	var max_y = y0 + w
	var max_x = x0 + h
	
	var terrain_size_x = input_heights.size()-1
	var terrain_size_y = 0
	if input_heights.size() > 0:
		terrain_size_y = input_heights[0].size()-1
	
	if max_y >= terrain_size_y:
		max_y = terrain_size_y
	if max_x >= terrain_size_x:
		max_x = terrain_size_x
	
	var vertices = Vector3Array()
	var normals = Vector3Array()
	var colors = ColorArray()
	var uv = Vector2Array()
	var indices = IntArray()
		
	var uv_scale = Vector2(1.0/terrain_size_x, 1.0/terrain_size_y)
	
	for y in range(y0, max_y+1):
		var hrow = input_heights[y]
		var crow = input_colors[y]
		var nrow = input_normals[y]
		for x in range(x0, max_x+1):
			vertices.push_back(Vector3(x-x0, hrow[x], y-y0))
			uv.push_back(Vector2(x, y) * uv_scale)
			colors.push_back(crow[x])
			normals.push_back(nrow[x])
	
	if vertices.size() == 0:
		print("No vertices generated! ", x0, ", ", y0, ", ", w, ", ", h)
		return null
	
	var vertex_count = vertices.size()
	var quad_count = (w-1)*(h-1)

	var i = 0
	for y in range(0, h):
		for x in range(0, w):
			indices.push_back(i)
			indices.push_back(i+w+2)
			indices.push_back(i+w+1)
			indices.push_back(i)
			indices.push_back(i+1)
			indices.push_back(i+w+2)
			i += 1
		i += 1
	
	var arrays = []
	arrays.resize(9)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var mesh = Mesh.new()
	mesh.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	return mesh

# Separating in two functions kinda sucks, but:
# 1) Vertices are laid out differently in faceted shading
# 2) SurfaceTool calculates normals for us
# 3) In GDScript that's a faster solution
static func make_heightmap_faceted(heights, colors, x0, y0, w, h):
	var st = SurfaceTool.new()
	
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	#st.add_smooth_group(true)
	
	var max_y = y0 + w
	var max_x = x0 + h
	
	var terrain_size_x = heights.size()-1
	var terrain_size_y = 0
	if heights.size() > 0:
		terrain_size_y = heights[0].size()-1
	
	if max_y >= terrain_size_y:
		max_y = terrain_size_y
	if max_x >= terrain_size_x:
		max_x = terrain_size_x
	
	var uv_scale = Vector2(1.0/terrain_size_x, 1.0/terrain_size_y)
	
	for y in range(y0, max_y):
		
		var row = heights[y]
		var color_row = colors[y]
		
		for x in range(x0, max_x):
			
			var p00 = Vector3(x-x0, row[x], y-y0)
			var p10 = Vector3(x+1-x0, row[x+1], y-y0)
			var p01 = Vector3(x-x0, heights[y+1][x], y+1-y0)
			var p11 = Vector3(x+1-x0, heights[y+1][x+1], y+1-y0)
			
			var uv00 = Vector2(x, y) * uv_scale
			var uv10 = Vector2(x+1, y) * uv_scale
			var uv11 = Vector2(x+1, y+1) * uv_scale
			var uv01 = Vector2(x, y+1) * uv_scale
			
			var c00 = color_row[x]
			var c10 = color_row[x+1]
			var c01 = colors[y+1][x]
			var c11 = colors[y+1][x+1]
			
			st.add_uv(uv00)
			st.add_color(c00)
			st.add_vertex(p00)
			
			st.add_uv(uv10)
			st.add_color(c10)
			st.add_vertex(p10)
			
			st.add_uv(uv11)
			st.add_color(c11)
			st.add_vertex(p11)
			
			st.add_uv(uv00)
			st.add_color(c00)
			st.add_vertex(p00)
			
			st.add_uv(uv11)
			st.add_color(c11)
			st.add_vertex(p11)
			
			st.add_uv(uv01)
			st.add_color(c01)
			st.add_vertex(p01)
	
	st.generate_normals()
	
	#st.index()
	var mesh = st.commit()
	return mesh
