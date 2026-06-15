module App
  class PlayScene
    attr_accessor :map, :camera, :zoom, :current_building, :world_mouse, :tick_count

    def initialize
      w = 50
      h = 50
      @tile_size = 32
      @current_wave = 0
      @map = App::Map.new(w: w, h: h, tile_size: @tile_size)
      @camera = SpriteKit::Camera.new(path: :camera)
      @spawn_tile = [@map.w / 2, @map.h - 2]
      @goal_tile = [@map.w / 2, 1]
      @enemies_to_spawn = 50
      # @zoom = {
      #   default: 1,
      #   minimum: 0.2,
      #   maximum: 4,
      #   increment: 0.2
      # }
      @zoom = {
        default: 0.7,   # ~14 tiles visible across
        minimum: 0.15,  # pulled back (WC3 max distance)
        maximum: 1.0,   # zoomed in over units
        increment: 0.05
      }

      @current_building = nil

      @buttons = {}
      @world_mouse = {x: 0, y: 0}
      @enemies = []
      @tick_count = 0

      3.times do |row|
        3.times do |col|
          index = row + (col * 3)
          sprite = SPRITES.cannon
          button = Layout.rect({
            row: row % 3 + (Layout.row_count - 3),
            col: col % 3 + (Layout.col_count - 4),
          }).merge(sprite)

          @buttons[index] = button

          button.on_click = proc { |world_mouse|
            @current_building = sprite.dup
            @current_building.x = world_mouse.x
            @current_building.y = world_mouse.y
          }
        end
      end
    end

    def tick(args)
      @debug_renderables = []
      render_camera_target(args)
      @world_mouse = @camera.to_world_space(args.inputs.mouse)

      if !@map.flow
        @map.compute_flow_field(*@goal_tile)
      end

      if @enemies_to_spawn != 0
        spawn_enemies
      end

      @inputs = args.inputs
      handle_input
      handle_camera_zoom
      calc(args)
      render(args)
      @tick_count += 1
    end

    def spawn_enemies
      return if @enemies_to_spawn.nil? || @enemies_to_spawn <= 0
      return if @tick_count % 60 != 0

      ts = @map.tile_size
      x = (@spawn_tile[0] + 0.5) * ts
      y = (@spawn_tile[1] + 0.5) * ts
      enemy_type = :goblin
      e = Enemy.new(engine: self, x: x, y: y, w: 32, h: 32, state: :walking, **SPRITES[enemy_type])
      e.target_x = x
      e.target_y = y
      @enemies << e
      @enemies_to_spawn -= 1
    end

    def calc(args)
      calc_camera

      if @current_building
        tile_size = @map.tile_size
        @current_building.w = tile_size * 2
        @current_building.h = tile_size * 2

        # tile coords of the building's bottom-left
        @placement_tx = ((@world_mouse.x - @current_building.w / 2) / tile_size).round
        @placement_ty = ((@world_mouse.y - @current_building.h / 2) / tile_size).round
        @placement_valid = @map.can_place?(@placement_tx, @placement_ty, 2, 2) &&
                            !@map.would_block_path?(@placement_tx, @placement_ty, 2, 2, @spawn_tile, @goal_tile) &&
                            !@map.creep_on_footprint?(@placement_tx, @placement_ty, 2, 2, @enemies, @map.tile_size)

        @current_building.x = @placement_tx * tile_size
        @current_building.y = @placement_ty * tile_size
        @camera.to_screen_space!(@current_building)

        @current_building_background = @current_building.dup.merge({
          path: :pixel,
          r: @placement_valid ? 0 : 255,
          g: @placement_valid ? 255 : 0,
          b: 0,
          a: 64
        })
      else
        @current_building_background = nil
      end

    end

    def render(args)
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

      # in render, alongside the chunk sprites
      building_sprites = @map.buildings_in_viewport(@camera).map do |b|
        sprite = b.dup
        @camera.to_screen_space!(sprite)
        sprite
      end

      grid = []
      grid = render_grid(camera: @camera, w: @map.tile_size, h: @map.tile_size) if @show_grid

      enemies = []

      Array.each(@enemies) do |e|
        e.state = :walking

        advance_enemy(e)

        e.update
        prefab = e.prefab
        prefab = [prefab] unless prefab.is_a?(Array)
        Array.each(prefab) { |spr| enemies << @camera.to_screen_space!(spr.dup) }
      end

      screen_renderables
        .concat(@debug_renderables)
        .concat(grid)
        .concat(building_sprites)
        .concat(enemies)
        .concat([@current_building_background, @current_building])

      args.outputs.primitives.concat(screen_renderables)

      args.outputs.primitives.concat([
        @camera.viewport,
      ]).concat(@buttons.values)

      args.outputs.primitives << DR.current_framerate_primitives
    end


    def handle_input
      inputs = @inputs
      speed = ((500 / @camera.scale) / 100) * (FPS / 45) # * 10

      edge = 12 # px from screen border
      mx = inputs.mouse.x
      my = inputs.mouse.y
      pan_up    = inputs.up    || my >= Grid.h - edge
      pan_down  = inputs.down  || my <= edge
      pan_right = inputs.right || mx >= Grid.w - edge
      pan_left  = inputs.left  || mx <= edge

      @camera.target_y += speed if pan_up
      @camera.target_y -= speed if pan_down
      @camera.target_x += speed if pan_right
      @camera.target_x -= speed if pan_left

      if inputs.keyboard.key_down.period
        @debug = !@debug
      end

      if inputs.keyboard.key_down.g
        @show_grid = !@show_grid
      end

      if inputs.mouse.click
        clicked_button = Geometry.find_intersect_rect(inputs.mouse, @buttons.values)

        if clicked_button
          clicked_button.on_click.call(inputs.mouse)
        elsif @current_building && @placement_valid
          @map.place_building!(@current_building, tile_x: @placement_tx, tile_y: @placement_ty)
          @map.compute_flow_field(*@goal_tile)
          # keep placing if shift held (classic TD UX), else exit placement mode
          @current_building = nil unless @inputs.keyboard.shift
        elsif inputs.mouse.button_right
          @current_building = nil  # cancel placement
        end
      end
    end

    def key_down_or_repeat?(*keys)
      keys.any? do |key|
        @inputs.keyboard.key_down?(key) || @inputs.keyboard.key_repeat?(key)
      end
    end

    def handle_camera_zoom
      # Zoom
      if key_down_or_repeat?(:equal_sign)
        @camera.target_scale += @zoom.increment
        @camera.target_scale = @zoom.maximum if @camera.target_scale > @zoom.maximum
      elsif key_down_or_repeat?(:minus)
        @camera.target_scale -= @zoom.increment
        @camera.target_scale = @zoom.minimum if @camera.target_scale < @zoom.minimum
      elsif @inputs.keyboard.zero
        @camera.target_scale = @zoom.default
      end

      wheel = @inputs.mouse.wheel
      if wheel
        @camera.target_scale += wheel.y * @zoom.increment
        @camera.target_scale = @camera.target_scale.clamp(@zoom.minimum, @zoom.maximum)
      end

    end

    def calc_camera
      # @camera.target_x = @player.x
      # @camera.target_y = @player.y
      lerp = 0.15
      # puts "#{@camera.target_scale}, #{@camera.scale}"
      @camera.scale += (@camera.target_scale - @camera.scale) * lerp
      @camera.x += (@camera.target_x - @camera.x) * lerp
      @camera.y += (@camera.target_y - @camera.y) * lerp
      clamp_camera!
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

    def clamp_camera!
      vp = @camera.viewport
      world_w = @map.w * @map.tile_size
      world_h = @map.h * @map.tile_size

      # half of the world area currently visible, in world units
      half_w = (vp.w / @camera.scale) * 0.5
      half_h = (vp.h / @camera.scale) * 0.5

      # clamp both the target and the actual position so zooming out
      # near an edge also gets corrected, not just panning
      @camera.target_x = clamp_axis(@camera.target_x, half_w, world_w - half_w)
      @camera.target_y = clamp_axis(@camera.target_y, half_h, world_h - half_h)
      @camera.x        = clamp_axis(@camera.x,        half_w, world_w - half_w)
      @camera.y        = clamp_axis(@camera.y,        half_h, world_h - half_h)
    end

    def clamp_axis(value, min, max)
      # if the view is wider than the world (zoomed way out), center instead
      return (min + max) * 0.5 if min > max
      value.clamp(min, max)
    end
    def advance_enemy(e)
      budget = (e.speed / 100) * (45 / 60)
      ts = @map.tile_size

      retarget_enemy(e)   # farthest visible waypoint from current position

      while budget > 0
        break if e.target_x.nil?

        dx = e.target_x - e.x
        dy = e.target_y - e.y
        dist = Math.sqrt(dx * dx + dy * dy)

        if dist <= budget
          e.x = e.target_x          # arrive exactly
          e.y = e.target_y
          budget -= dist            # spend only what the hop cost
          retarget_enemy(e)         # arrived mid-tick; re-pull a new target
          break if e.target_x.nil?  # reached the goal
        else
          e.x += (dx / dist) * budget   # move at fixed speed along the heading
          e.y += (dy / dist) * budget
          budget = 0
        end
      end
    end

    def retarget_enemy(e)
      ts = @map.tile_size
      tx = (e.x / ts).floor
      ty = (e.y / ts).floor

      path = @map.lookahead_path(tx, ty)
      if path.empty?
        e.target_x = nil
        e.target_y = nil
        return
      end

      chosen = path.first   # safe fallback: the immediate field step (always adjacent)
      path.each do |(px, py)|
        cx = (px + 0.5) * ts
        cy = (py + 0.5) * ts
        if @map.los_clear?(e.x, e.y, cx, cy)
          chosen = [px, py]
        else
          break               # string-pull: stop at first node we can't see
        end
      end

      e.target_x = (chosen[0] + 0.5) * ts
      e.target_y = (chosen[1] + 0.5) * ts
    end
  end
end
