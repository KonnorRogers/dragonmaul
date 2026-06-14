module App
  class Map
    attr_accessor :w, :h, :tile_size, :tiles, :chunk_px

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
          return false if x < 0 || y < 0 || x >= @w || y >= @h
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
  end
end
