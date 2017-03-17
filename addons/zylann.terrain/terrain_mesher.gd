tool

# heights: array of arrays of floats
# normals: arrays of arrays of Vector3
# x0, y0, w, h: sub-rectangle to generate from the above grids
# smooth_shading: if set to true, normals will be used instead of "polygon-looking" ones
# quad_adaptation: experimental. If true, quad geometry will be flipped in some situations for better shading.
# returns: a Mesh
static func make_heightmap(heights, normals, x0, y0, w, h, smooth_shading=true, quad_adaptation=false):
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
		var normal_row = normals[y]
		for x in range(x0, max_x):
			
			var p00 = Vector3(x-x0, row[x], y-y0)
			var p10 = Vector3(x+1-x0, row[x+1], y-y0)
			var p01 = Vector3(x-x0, heights[y+1][x], y+1-y0)
			var p11 = Vector3(x+1-x0, heights[y+1][x+1], y+1-y0)
			
			var uv00 = Vector2(x, y) * uv_scale
			var uv10 = Vector2(x+1, y) * uv_scale
			var uv11 = Vector2(x+1, y+1) * uv_scale
			var uv01 = Vector2(x, y+1) * uv_scale
			
			# TODO This is where optimization becomes a pain.
			# Find a way to use arrays instead of interleaved data. SurfaceTool is bad at this...
			# What if we don't want UVs? AAAAAAAAAAAAAAHHH
			# See? In C++, you do a lookup table. In GDScript, you don't, because it's TOO DAMN SLOW :D
		
			var reverse_quad = quad_adaptation and abs(p00.y - p11.y) > abs(p10.y - p01.y)
			
			if smooth_shading:
				
				var n00 = normal_row[x]
				var n10 = normal_row[x+1]
				var n01 = normals[y+1][x]
				var n11 = normals[y+1][x+1]
				
				if reverse_quad:
					# 01---11
					#  |\  |
					#  | \ |
					#  |  \|
					# 00---10
					
					st.add_normal(n00)
					st.add_uv(uv00)
					st.add_vertex(p00)
					
					st.add_normal(n10)
					st.add_uv(uv10)
					st.add_vertex(p10)
					
					st.add_normal(n01)
					st.add_uv(uv01)
					st.add_vertex(p01)
		
					st.add_normal(n10)
					st.add_uv(uv10)
					st.add_vertex(p10)
					
					st.add_normal(n11)
					st.add_uv(uv11)
					st.add_vertex(p11)
					
					st.add_normal(n01)
					st.add_uv(uv01)
					st.add_vertex(p01)
					
				else:
					# 01---11
					#  |  /|
					#  | / |
					#  |/  |
					# 00---10
					
					st.add_normal(n00)
					st.add_uv(uv00)
					st.add_vertex(p00)
					
					st.add_normal(n10)
					st.add_uv(uv10)
					st.add_vertex(p10)
					
					st.add_normal(n11)
					st.add_uv(uv11)
					st.add_vertex(p11)
		
					st.add_normal(n00)
					st.add_uv(uv00)
					st.add_vertex(p00)
					
					st.add_normal(n11)
					st.add_uv(uv11)
					st.add_vertex(p11)
					
					st.add_normal(n01)
					st.add_uv(uv01)
					st.add_vertex(p01)
			
			else:
				if reverse_quad:
					st.add_uv(uv00)
					st.add_vertex(p00)
					
					st.add_uv(uv10)
					st.add_vertex(p10)
					
					st.add_uv(uv01)
					st.add_vertex(p01)
		
					st.add_uv(uv10)
					st.add_vertex(p10)
					
					st.add_uv(uv11)
					st.add_vertex(p11)
					
					st.add_uv(uv01)
					st.add_vertex(p01)
				
				else:
					st.add_uv(uv00)
					st.add_vertex(p00)
					
					st.add_uv(uv10)
					st.add_vertex(p10)
					
					st.add_uv(uv11)
					st.add_vertex(p11)
		
					st.add_uv(uv00)
					st.add_vertex(p00)
					
					st.add_uv(uv11)
					st.add_vertex(p11)
					
					st.add_uv(uv01)
					st.add_vertex(p01)
					
	# When smoothing is active, we can't rely on automatic normals,
	# because they would produce seams at the edges of chunks,
	# so instead we generate the normals from the actual terrain data
	if not smooth_shading:
		st.generate_normals()

	st.index()
	var mesh = st.commit()
	return mesh
