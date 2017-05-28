tool

class QuadtreeNode:
	# If the node has children, this will be an array of 4 nodes
	var children = null
	# If children is null, this will be set to a chunk.
	# If the chunk is still null, it's pending generation.
	var chunk = null
	# Origin of the node, relative to its lod level
	var origin = Vector2()

var make_chunk_func = null
var recycle_chunk_func = null

# Quad tree for LOD computation
var _tree = null
# One grid per lod for contiguous access
var _grids = []

var _base_size = 16
var _max_depth = 4


func _init():
	#from_sizes(16, 256)
	reset()


func get_chunk_at(x, y, lod=0):
	var grid = _grids[lod]
	var k = Vector2(x,y)
	if grid.has(k):
		return grid[k]
	return null


func get_lod_count():
	return _max_depth


func reset():
	_for_all_nodes(funcref(self, "_clear_node_cb"))
	_tree = QuadtreeNode.new()
	var r = get_lod_size(_max_depth)
	_tree.origin = Vector2(0,0)

func _clear_node_cb(node, lod_index):
	if node.chunk != null:
		_recycle_chunk(node.chunk, node.origin, lod_index)
		node.chunk = null


func from_sizes(base_size, full_size):
	var po = 0
	while full_size > base_size:
		full_size = full_size >> 1
		po += 1
	#print(po)
	_base_size = base_size
	_max_depth = po
	
	_grids.resize(po+1)
	for i in range(0, _grids.size()):
		_grids[i] = {}
	#print("Grids: ", _grids.size())
	
	reset()


# TODO That would be simpler with lambdas!
func for_all_chunks(action_cb):
	if _tree != null:
		_for_all_chunks_recursive(action_cb, _tree, _max_depth)

func _for_all_chunks_recursive(action_cb, node, lod_index):
	if node.children != null:
		for child in node.children:
			_for_all_chunks_recursive(action_cb, child, lod_index-1)
	else:
		if node.chunk != null:
			action_cb.call_func(node.chunk, lod_index)

# Copy paste from above...
func _for_all_nodes(action_cb):
	if _tree != null:
		_for_all_nodes_recursive(action_cb, _tree, _max_depth)

func _for_all_nodes_recursive(action_cb, node, lod_index):
	if node.children != null:
		for child in node.children:
			_for_all_nodes_recursive(action_cb, child, lod_index-1)
	else:
		action_cb.call_func(node, lod_index)


func update_now(viewer_pos):
	_update_nodes_recursive(_tree, _max_depth, viewer_pos)
	_make_chunks_recursively(_tree, _max_depth)


func _recycle_chunk(chunk, origin, lod_index):
	#print("Recycle ", OS.get_ticks_msec())
	if recycle_chunk_func != null:
		recycle_chunk_func.call_func(chunk)
	_grids[lod_index].erase(origin)


func _make_chunk(lod_index, origin):
	#print("Recycle ", origin)
	var chunk = null
	if make_chunk_func != null:
		chunk = make_chunk_func.call_func(lod_index, origin)
	if chunk == null:
		# Placeholder output
		chunk = true
	if chunk != null:
		_grids[lod_index][origin] = chunk
	return chunk


func _update_nodes_recursive(node, lod_index, viewer_pos):
	var lod_size = get_lod_size(lod_index)
	#var world_center = _base_size * (Vector3(node.origin.x, 0, node.origin.y) + Vector3(lod_size,0,lod_size)*0.5)
	var world_center = (_base_size*lod_size) * (Vector3(node.origin.x, 0, node.origin.y) + Vector3(0.5, 0, 0.5))
	
	var split_distance = get_split_distance(lod_index)
	
	if node.children != null:
		# Test if it should be joined
		# TODO Distance should take the chunk's Y dimension into account
		if world_center.distance_to(viewer_pos) > split_distance:
			_join_recursively(node, lod_index)
	
	elif lod_index > 0:
		# Test if it should split
		if world_center.distance_to(viewer_pos) < split_distance:
			# Split
			var children = []
			children.resize(4)
			
			for i in range(0, children.size()):
				var j = int(round(i)) # https://github.com/godotengine/godot/issues/8278
				var child = QuadtreeNode.new()
				child.origin = node.origin*2 + Vector2( j&1, (j&2)>>1 )
				#child.chunk = make_chunk(lod_index-1, child.origin)
				children[i] = child
			
			node.children = children
			if node.chunk != null:
				_recycle_chunk(node.chunk, node.origin, lod_index)
			node.chunk = null
	
	# TODO This will check all chunks every frame,
	# we could find a way to recursively update chunks as they get joined/split,
	# but in C++ that would be not even needed.
	if node.children != null:
		var children = node.children
		for i in range(0, children.size()):
			_update_nodes_recursive(children[i], lod_index-1, viewer_pos)


func _join_recursively(node, lod_index):
	if node.children != null:
		for i in range(0, node.children.size()):
			var child = node.children[i]
			_join_recursively(child, lod_index-1)
		node.children = null
	elif node.chunk != null:
		_recycle_chunk(node.chunk, node.origin, lod_index)
		node.chunk = null


func _make_chunks_recursively(node, lod_index):
	assert(lod_index >= 0)
	if node.children != null:
		for i in range(0, node.children.size()):
			var child = node.children[i]
			_make_chunks_recursively(child, lod_index-1)
	else:
		if node.chunk == null:
			node.chunk = _make_chunk(lod_index, node.origin)
			# Note: if you don't return anything here,
			# make_chunk will continue being called

func get_lod_size(lod_index):
	return 1 << lod_index

func get_split_distance(lod_index):
	# TODO Should be tweakable
	return _base_size * get_lod_size(lod_index) * 2.0


# Takes a rectangle in highest LOD coordinates,
# and calls a function on all chunks of that LOD or higher LODs.
func for_chunks_in_rect(action_cb, cx0, cy0, cw, ch):
	# For each lod
	for lod_index in range(0, _grids.size()):
		# Get grid and chunk size
		var grid = _grids[lod_index]
		var s = get_lod_size(lod_index)
		
		# Convert rect into this lod's coordinates
		var min_x = cx0 / s
		var min_y = cy0 / s
		var max_x = (cx0 + cw) / s + 1
		var max_y = (cy0 + ch) / s + 1
		
		# Find which chunks are within
		for cy in range(min_y, max_y):
			for cx in range(min_x, max_x):
				var k = Vector2(cx,cy)
				if grid.has(k):
					var chunk = grid[k]
					action_cb.call_func(chunk, k, lod_index)

# Debug functions


func debug_draw_grid(ci):
	for lod_index in range(0, _grids.size()):
		var grid = _grids[lod_index]
		var lod_size = get_lod_size(lod_index)
		for k in grid:
			var checker = 0
			if int(k.y)%2 == 1:
				if int(k.x)%2 == 0:
					checker = 1
			else:
				if int(k.x)%2 == 1:
					checker = 1
			ci.draw_rect(Rect2(k, Vector2(lod_size, lod_size)), Color(1.0-lod_index*0.2, 0.2*checker, 0, 1))


func debug_draw_tree(ci):
	var node = _tree
	_debug_draw_tree_recursive(ci, node, _max_depth, 0)


func _debug_draw_tree_recursive(ci, node, lod_index, child_index):
	if node.children == null:
		var size = get_lod_size(lod_index)
		var checker = 0
		if child_index == 1 or child_index == 2:
			checker = 1
		var chunk_indicator = 0
		if node.chunk != null:
			chunk_indicator = 1
		ci.draw_rect(Rect2(node.origin*size, Vector2(size,size)), Color(1.0-lod_index*0.2,0.2*checker,chunk_indicator,1))
	else:
		for i in range(0, node.children.size()):
			var child = node.children[i]
			_debug_draw_tree_recursive(ci, child, lod_index-1, i)
