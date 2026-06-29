module App
  class Map
    attr_accessor :w, :h, :tile_size, :tiles, :chunk_px, :occupied, :buildings, :camera_start, :spawn_points, :goal, :goal_tile, :waypoints, :ground_bits, :occupied_bits

    CHUNK_TILES = 32  # 32x32 tiles per chunk = 512px at tile_size 16

    def initialize(w:, h:, tile_size: 128)
      @w = w
      @h = h
      @tile_size = tile_size

      @chunk_px = CHUNK_TILES * @tile_size
      @occupied = {}
      @buildings = {}

      @camera_start = {
        x: 0,
        y: 0,
      }


      # generate
      load_level

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

    def load_level(level = 0)
      full_file = "data/maps/dragonmaul/level_#{level}.ldtkl"
      full_data = DR.parse_json_file(full_file)
      dir = "data/maps/dragonmaul/simplified/level_#{level}"
      data = DR.parse_json_file("#{dir}/data.json")
      w = data["width"]
      h = data["height"]
      layers = data["layers"]

      # For some reason the simplified int grid only writes 256 columns, instead of the ~900 or so.
      # int_grid = DR.read_file("#{dir}/int_grid.csv")
      int_grid = full_data["layerInstances"].find do |hash|
        hash["__identifier"] == "int_grid"
      end

      int_grid_csv = int_grid["intGridCsv"]


      @w = int_grid["__cWid"].to_i
      @h = int_grid["__cHei"].to_i

      @tiles = {}
      grid_size = int_grid["__gridSize"]   # px-per-cell LDtk authored with (likely 16)
      cam = data["entities"]["camera_start"][0]

      @camera_start = {
        x: (cam["x"] / grid_size) * @tile_size,
        y: (cam["y"] / grid_size) * @tile_size,
      }

      @spawn_points = []

      data["entities"]["spawn_points"].each do |point|
        # y is flipped in DR compared to LDTK
        y = h - point["y"] - 100
        @spawn_points << {
          x: ((point["x"] / grid_size) * (@tile_size / grid_size)).to_i,
          y: ((y / grid_size) * (@tile_size / grid_size)).to_i,
        }

      end

      @goal_tile = {}
      goal = data["entities"]["goal"][0]
      @goal_tile.x = (goal["x"] / grid_size).to_i
      @goal_tile.y = ((h - goal["y"]) / grid_size).to_i

      @goal = {
        x: @goal_tile.x * @tile_size,
        y: @goal_tile.y * @tile_size,
        w: @tile_size * 3,
        h: @tile_size * 3,
      }

      waypoints = data["entities"]["waypoints"]

      @waypoints = []
      waypoints.each do |wp|
        @waypoints << {
          x: (wp["x"] / grid_size).to_i,
          y: ((h - wp["y"]) / grid_size).to_i,
          order: (wp.dig("customFields", "order")) || 0,
        }
      end

      int_grid_csv.each_with_index do |value, i|
        next if value.zero?           # skip empty cells

        x = i % @w
        y = @h - 1 - (i / @w).floor

        @tiles[chunk_key(x, y)] = :ground
      end
      # puts "columns: #{col}, rows: #{row}"
      # end of load_level, after @tiles is fully populated:
      @ground_bits   = Array.new(@w * @h, false)
      @occupied_bits = Array.new(@w * @h, false)
      @tiles.each_key do |key|
        cx = key & 0xFFFF
        cx -= 65_536 if cx > 32_767
        cy = key >> 16
        @ground_bits[cy * @w + cx] = true
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
          x = tx + dx; y = ty + dy
          @occupied[chunk_key(x, y)] = building
          @occupied_bits[y * @w + x] = true if x >= 0 && y >= 0 && x < @w && y < @h
        end
      end
    end

    def can_place?(tx, ty, w_tiles, h_tiles, enemies)
      w_tiles.times do |dx|
        h_tiles.times do |dy|
          x = tx + dx
          y = ty + dy
          return false if (x < 0 || y < 0) || (x >= @w || y >= @h)
          return false if occupied?(x, y)
          return false unless @tiles[chunk_key(x, y)] == :ground # buildable terrain only
          return false if Geometry.find_intersect_rect({
            x: (x * @tile_size).floor,
            y: (y * @tile_size).floor,
            w: @tile_size,
            h: @tile_size
          }, enemies)
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

    def place_building!(building, tile_x:, tile_y:)
      tile_size = @tile_size
      building = building.dup
      building.x = tile_x * tile_size
      building.y = tile_y * tile_size
      building.w = tile_size * building.tiles
      building.h = tile_size * building.tiles
      building.hp = 100
      building.id = DR.create_uuid

      occupy!(tile_x, tile_y, building.tiles, building.tiles, building)
      @buildings[building.id] = building
      building
    end

    def damage_building!(building, amount)
      building.hp -= amount
      # building.hp -= 33
      return false if building.hp > 0
      remove_building!(building)
      true   # destroyed this hit
    end

    def remove_building!(building)
      bx = (building.x / @tile_size).to_i
      by = (building.y / @tile_size).to_i
      building.tiles.times do |dx|
        building.tiles.times do |dy|
          x = bx + dx; y = by + dy
          @occupied.delete(chunk_key(x, y))
          @occupied_bits[y * @w + x] = false if x >= 0 && y >= 0 && x < @w && y < @h
        end
      end
      @buildings.delete(building.id)
    end
  end
end
