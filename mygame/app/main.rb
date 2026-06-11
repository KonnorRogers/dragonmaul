require "vendor/sprite_kit/sprite_kit.rb"

module Main
  FPS = 60
  attr_accessor :game

  def tick(args)
    @game ||= Game.new
    @game.tick(args)
  end

  def reset(args)
    @game = nil
  end

  SPRITES = {
    ground: {
      source_x: 32,
      source_y: 96,
      source_h: 32,
      source_w: 32,
      path: "sprites/craftpix/4_gui/1_interface/tileset.png",
    },
    wall: {
    }
  }

  class Game
    attr_accessor :scene
    def initialize
      @scenes = {
        play_scene: lambda {
          PlayScene.new
        },
        spritesheet_scene: lambda {
          SpriteKit::Scenes::SpritesheetScene.new.tap do |scene|
            scene.state.tile_selection = {
              w: 32, h: 32,
              row_gap: 0, column_gap: 0,
              offset_x: 0, offset_y: 0,
            }
          end
        }
      }

      @scene_key = :play_scene
      @scene = @scenes[@scene_key].call
    end

    def tick(args)
      @scene.tick(args)

      # Make this less icky
      if args.inputs.keyboard.key_down.close_square_brace
        scene_keys = @scenes.keys
        current_scene_index = scene_keys.find_index { |key| key == @scene_key } + 1
        if current_scene_index > scene_keys.length - 1
          current_scene_index = 0
        end

        if current_scene_index < 0
          current_scene_index = 0
        end

        @next_scene = scene_keys[current_scene_index]
      end

      if @next_scene
        @scene = @scenes[@next_scene].call
        @scene_key = @next_scene
        @next_scene = nil
      end
    end
  end

  class PlayScene
    def initialize
      size = 500
      @map = Map.new(w: size, h: size)
      @camera = SpriteKit::Camera.new(path: :camera)
      @zoom = {
        default: 1,
        minimum: 0.25,
        maximum: 4,
        increment: 0.25
      }
    end

    def tick(args)
      @debug_renderables = []
      render_camera_target(args)
      @world_mouse = @camera.to_world_space(args.inputs.mouse)

      @inputs = args.inputs
      handle_input
      handle_camera_zoom
      calc_camera

      size = @map.chunk_px
      screen_renderables = @map.chunks_in_viewport(@camera).map do |c|
        @map.ensure_chunk_rendered(args, c.cx, c.cy)
        sprite = { x: c.cx * size, y: c.cy * size, w: size, h: size, path: @map.rt_name(c.cx, c.cy) }


        @camera.to_screen_space!(sprite)

        if @debug
          @debug_renderables.concat(SpriteKit::Primitives.borders(
            {
              x: sprite.x,
              y: sprite.y,
              w: sprite.w,
              h: sprite.h,
            },
            color: { r: 0, g: 255, b: 255, a: 200 }
          ).values)
        end
        sprite
      end

      grid = []

      grid = render_grid(camera: @camera, w: @map.tile_size, h: @map.tile_size) if @show_grid
      args.outputs.primitives
        .concat(screen_renderables)
        .concat(@debug_renderables)
        .concat(grid)

      args.outputs.primitives.concat([
        {
          **@camera.viewport,
        }
      ])

      args.outputs.primitives << DR.current_framerate_primitives
    end

    def handle_input
      inputs = @inputs
      speed = ((300 / @camera.scale) / 100) * (FPS / 45) # * 10

      if inputs.up
        @camera.target_y += speed
      end

      if inputs.down
        @camera.target_y -= speed
      end

      if inputs.right
        @camera.target_x += speed
      end

      if inputs.left
        @camera.target_x -= speed
      end

      if inputs.keyboard.key_down.period
        @debug = !@debug
      end

      if inputs.keyboard.key_down.g
        @show_grid = !@show_grid
      end
    end

    def handle_camera_zoom
      # Zoom
      if @inputs.keyboard.key_down.equal_sign || @inputs.keyboard.key_down.plus
        @camera.target_scale += @zoom.increment
        @camera.target_scale = @zoom.maximum if @camera.target_scale > @zoom.maximum
      elsif @inputs.keyboard.key_down.minus
        @camera.target_scale -= @zoom.increment
        @camera.target_scale = @zoom.minimum if @camera.target_scale < @zoom.minimum
      elsif @inputs.keyboard.zero
        @camera.target_scale = @zoom.default
      end
    end

    def calc_camera
      # @camera.target_x = @player.x
      # @camera.target_y = @player.y

      @camera.scale += (@camera.target_scale - @camera.scale)
      @camera.x += (@camera.target_x - @camera.x)
      @camera.y += (@camera.target_y - @camera.y)
    end

    def render_camera_target(args)
      camera_rt = args.outputs[@camera.path]
      viewport = @camera.viewport
      camera_rt.w = viewport.w
      camera_rt.h = viewport.h
      camera_rt.background_color = [0,0,0,0]
    end

    def render_grid(camera:, w: @tile_size, h: @tile_size)
      world = camera.to_world_space!(@camera.viewport.dup)
      puts "WORLD: #{world}"
      min_x = [(world.x / w).floor * w, 0].max
      min_y = [(world.y / h).floor * h, 0].max
      max_x = world.x + world.w
      max_y = world.y + world.h

      solids = []

      x = min_x
      while x <= max_x
        s = { x: x, y: min_y, w: 1, h: max_y - min_y }
        camera.to_screen_space!(s)
        solids << { x: s.x, y: s.y, w: 1, h: s.h, r: 255, g: 255, b: 255, a: 255, path: :solid }
        x += w
      end

      y = min_y
      while y <= max_y
        s = { x: min_x, y: y, w: max_x - min_x, h: 1 }
        camera.to_screen_space!(s)
        solids << { x: s.x, y: s.y, w: s.w, h: 1, r: 255, g: 255, b: 255, a: 255, path: :solid }
        y += h
      end

      solids
    end
  end

  class Map
    attr_accessor :w, :h, :tile_size, :tiles, :chunk_px

    CHUNK_TILES = 32  # 32x32 tiles per chunk = 512px at tile_size 16

    def initialize(w:, h:, tile_size: 16)
      @w = w
      @h = h
      @tile_size = tile_size

      @chunk_px = CHUNK_TILES * @tile_size

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
      rt.w = chunk_px
      rt.h = chunk_px
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
      size = chunk_px
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

  end
end
