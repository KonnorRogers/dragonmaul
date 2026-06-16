module App
  class Map
    attr_accessor :w, :h, :tile_size, :tiles, :chunk_px, :flow

    NEIGHBORS = [[1, 0], [-1, 0], [0, 1], [0, -1]]
    DIAGONALS = [[1, 1], [1, -1], [-1, 1], [-1, -1]]
    CHUNK_TILES = 32  # 32x32 tiles per chunk = 512px at tile_size 16

    def initialize(w:, h:, tile_size: 128)
      @w = w
      @h = h
      @tile_size = tile_size

      @chunk_px = CHUNK_TILES * @tile_size
      @occupied = {}
      @buildings = {}

      generate
    end

    # Pack individual tile coords into a hash key
    def chunk_key(cx, cy)
      (cy << 16) | (cx & 0xFFFF)
    end

    def chunk_key_to_cx(key)  (key & 0xFFFF).then { |v| v > 32767 ? v - 65536 : v }  end
    def chunk_key_to_cy(key)  key >> 16  end

    def generate
      @tiles = {}
      @w.times do |row|
        @h.times do |col|
          @tiles[chunk_key(row, col)] = :ground
        end
      end
    end

    def tiles_in_viewport(camera, largest_tile: @tile_size)
      world = camera.to_world_space!(camera.viewport.dup)

      min_x = ((world.x - largest_tile) / @tile_size).floor * @tile_size
      min_y = ((world.y - largest_tile) / @tile_size).floor * @tile_size
      max_x = world.x + world.w + largest_tile
      max_y = world.y + world.h + largest_tile

      result = []
      x = min_x
      while x <= max_x
        y = min_y
        while y <= max_y
          tile_x = x.idiv(@tile_size)
          tile_y = y.idiv(@tile_size)
          sym = @tiles[chunk_key(tile_x, tile_y)]

          if sym
            result << { x: x, y: y, w: @tile_size, h: @tile_size, **SPRITES[sym] }
          end

          y += @tile_size
        end
        x += @tile_size
      end
      result
    end

    def rt_name(cx, cy)
      :"chunk_#{cx}_#{cy}"
    end

    # Bake a chunk into a render target, once
    def ensure_chunk_rendered(args, cx, cy)
      @rendered_chunks ||= {}
      key = chunk_key(cx, cy)
      return if @rendered_chunks[key]
      @rendered_chunks[key] = true

      rt = args.outputs[rt_name(cx, cy)]
      rt.w = @chunk_px
      rt.h = @chunk_px
      rt.background_color = [0, 0, 0, 0]

      sprites = []
      CHUNK_TILES.times do |tx|
        CHUNK_TILES.times do |ty|
          sym = @tiles[chunk_key(cx * CHUNK_TILES + tx, cy * CHUNK_TILES + ty)]
          next unless sym
          sprites << {
            x: tx * @tile_size, y: ty * @tile_size,
            w: @tile_size, h: @tile_size,
            **SPRITES[sym]
          }
        end
      end
      rt.primitives.concat(sprites)
    end

    def chunks_in_viewport(camera)
      world = camera.to_world_space!(camera.viewport.dup)
      size = @chunk_px
      min_cx = (world.x / size).floor
      min_cy = (world.y / size).floor
      max_cx = ((world.x + world.w) / size).floor
      max_cy = ((world.y + world.h) / size).floor

      result = []
      (min_cx..max_cx).each do |cx|
        (min_cy..max_cy).each do |cy|
          result << { cx: cx, cy: cy } if chunk_exists?(cx, cy)
        end
      end
      result
    end

    def chunk_exists?(cx, cy)
      cx >= 0 && cy >= 0 &&
        cx * CHUNK_TILES < @w &&
        cy * CHUNK_TILES < @h
    end

    def occupied?(tx, ty)
      @occupied.key?(chunk_key(tx, ty))
    end

    def occupy!(tx, ty, w_tiles, h_tiles, building)
      w_tiles.times do |dx|
        h_tiles.times do |dy|
          @occupied[chunk_key(tx + dx, ty + dy)] = building
        end
      end
    end

    def can_place?(tx, ty, w_tiles, h_tiles)
      w_tiles.times do |dx|
        h_tiles.times do |dy|
          x = tx + dx
          y = ty + dy
          return false if (x < 0 || y < 0) || (x >= @w || y >= @h)
          return false if occupied?(x, y)
          return false unless @tiles[chunk_key(x, y)] == :ground # buildable terrain only
        end
      end
      true
    end

    def buildings_in_viewport(camera)
      world = camera.to_world_space!(camera.viewport.dup)
      min_tx = (world.x / @tile_size).floor - 4  # pad by max building size in tiles
      min_ty = (world.y / @tile_size).floor - 4
      max_tx = ((world.x + world.w) / @tile_size).ceil
      max_ty = ((world.y + world.h) / @tile_size).ceil

      seen = {}
      result = []
      (min_tx..max_tx).each do |tx|
        (min_ty..max_ty).each do |ty|
          b = @occupied[chunk_key(tx, ty)]
          next unless b
          next if seen[b.object_id]
          seen[b.object_id] = true
          result << b
        end
      end
      result
    end

    def place_building!(building, tile_x:, tile_y:, w: 2, h: 2)
      tile_size = @tile_size
      building = building.dup
      building.x = tile_x * tile_size
      building.y = tile_y * tile_size
      building.w = tile_size * w
      building.h = tile_size * h

      occupy!(tile_x, tile_y, w, h, building)
      @buildings << building
    end

    def compute_flow_field(goal_tx, goal_ty)
      @flow = {}
      @flow[chunk_key(goal_tx, goal_ty)] = 0
      queue = [[goal_tx, goal_ty]]
      head = 0
      while head < queue.length
        tx, ty = queue[head]
        head += 1
        d = @flow[chunk_key(tx, ty)]
        NEIGHBORS.each do |dx, dy|
          nx = tx + dx
          ny = ty + dy
          next if nx < 0 || ny < 0 || nx >= @w || ny >= @h
          nkey = chunk_key(nx, ny)
          next if @flow.key?(nkey)     # already visited
          next if occupied?(nx, ny)    # buildings block the flow
          @flow[nkey] = d + 1
          queue << [nx, ny]
        end
      end
    end

    # For a creep on tile (tx,ty): the neighbor with the lowest distance.
    def next_step(tx, ty)
      here = @flow[chunk_key(tx, ty)]

      # creep is on a tile with no flow value (e.g. a building was just
      # dropped on it) — escape to any neighbor that has a distance
      if here.nil?
        best = nil
        best_d = nil
        (NEIGHBORS + DIAGONALS).each do |dx, dy|
          d = @flow[chunk_key(tx + dx, ty + dy)]
          if d && (best_d.nil? || d < best_d)
            best_d = d
            best = [tx + dx, ty + dy]
          end
        end
        return best
      end

      best = nil
      best_d = here
      NEIGHBORS.each do |dx, dy|
        d = @flow[chunk_key(tx + dx, ty + dy)]
        if d && d < best_d
          best_d = d
          best = [tx + dx, ty + dy]
        end
      end
      DIAGONALS.each do |dx, dy|
        next if occupied?(tx + dx, ty) || occupied?(tx, ty + dy)
        # Add +0.4 for diagonals as they cost extra to move.
        d = @flow[chunk_key(tx + dx, ty + dy)]
        if d && (d + 0.4) < best_d
          best_d = d
          best = [tx + dx, ty + dy]
        end
      end
      best
    end

    def creep_on_footprint?(tx, ty, w, h, enemies, ts)
      enemies.any? do |e|
        ex = (e.x / ts).floor
        ey = (e.y / ts).floor
        ex >= tx && ex < tx + w && ey >= ty && ey < ty + h
      end
    end

    def would_block_path?(tx, ty, w, h, spawn, goal)
      blocked = {}
      w.times { |dx| h.times { |dy| blocked[chunk_key(tx + dx, ty + dy)] = true } }

      visited = { chunk_key(goal[0], goal[1]) => true }
      queue = [goal]
      head = 0
      while head < queue.length
        cx, cy = queue[head]; head += 1
        return false if cx == spawn[0] && cy == spawn[1]   # goal reaches spawn → not blocked
        NEIGHBORS.each do |dx, dy|
          nx = cx + dx; ny = cy + dy
          next if nx < 0 || ny < 0 || nx >= @w || ny >= @h
          k = chunk_key(nx, ny)
          next if visited[k] || occupied?(nx, ny) || blocked[k]
          visited[k] = true
          queue << [nx, ny]
        end
      end
      true   # never reached spawn → it would wall off the maze
    end
  end
end
