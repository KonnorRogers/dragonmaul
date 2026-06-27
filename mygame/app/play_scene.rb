module App
  class PlayScene
    attr_accessor :map, :camera, :zoom, :current_building, :world_mouse, :tick_count

    PALETTE = {
      white: {
        r: 255,
        b: 255,
        g: 255,
        a: 255
      },
      blocked_tile: {
        r: 255,
        g: 0,
        b: 0,
        a: 68
      }
    }

    def initialize
      w = 20
      h = 50
      @tile_size = 16
      @current_wave = 0
      @map = App::Map.new(w: w, h: h, tile_size: @tile_size)
      @graph = Graph.new(map: @map)
      @camera = SpriteKit::Camera.new(path: :camera)

      @enemies_to_spawn = 50
      # @zoom = {
      #   default: 1,
      #   minimum: 0.2,
      #   maximum: 4,
      #   increment: 0.2
      # }
      @zoom = {
        default: 1,   # ~14 tiles visible across
        minimum: 0.15,  # pulled back (WC3 max distance)
        maximum: 1.0,   # zoomed in over units
        increment: 0.05
      }

      @camera.target_x = @map.camera_start.x
      @camera.x = @map.camera_start.x
      @camera.target_y = @map.camera_start.y
      @camera.y = @map.camera_start.y
      @camera.scale = @zoom[:default]
      @camera.target_scale = @zoom[:default]

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

      # __debug_x_movement
    end

    def tick(args)
      args.outputs.debug << "#{@map.camera_start}"
      args.outputs.debug << "#{@camera.scale}; #{@camera.x}, #{@camera.y}"
      @debug_renderables = []
      render_camera_target(args)
      @world_mouse = @camera.to_world_space(args.inputs.mouse)

      if !@graph.flow
        # the initial one, and inside place_building! / attack_tower
        @graph.compute(@map.goal_tile)
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

      @map.spawn_points.each do |spawn_point|
        ts = @map.tile_size
        x = (spawn_point.x + 0.5) * ts
        y = (spawn_point.y + 0.5) * ts
        enemy_type = :goblin
        e = Enemy.new(engine: self, x: x, y: y, w: 32, h: 32, state: :walking, **SPRITES[enemy_type])
        e.target_x = x
        e.target_y = y
        @enemies << e
        @enemies_to_spawn -= 1
      end
    end

    def calc(args)
      calc_camera

      if @current_building
        tile_size = @map.tile_size
        @current_building.w = tile_size * @current_building.tiles
        @current_building.h = tile_size * @current_building.tiles

        # tile coords of the building's bottom-left
        @placement_tx = ((@world_mouse.x - (@current_building.w / 2)) / tile_size).round
        @placement_ty = ((@world_mouse.y - (@current_building.h / 2)) / tile_size).round
        @placement_valid = @map.can_place?(@placement_tx, @placement_ty, @current_building.tiles, @current_building.tiles, @enemies)

        @current_building.x = @placement_tx * tile_size
        @current_building.y = @placement_ty * tile_size

        @current_building_background = []

        # Render grid around tile
        # how many tiles of grid to show on each side
        # tiles_around = 1
        # region = {
        #   x: @current_building.x - tiles_around * @tile_size,
        #   y: @current_building.y - tiles_around * @tile_size,
        #   w: @current_building.w + tiles_around * 2 * @tile_size,
        #   h: @current_building.h + tiles_around * 2 * @tile_size,
        # }
        # @current_building_background.concat(render_grid(region: region, show_blocked: true))

        @camera.to_screen_space!(@current_building)   # fine to mutate now — we're done reading it

        @current_building.tiles.times do |tile_x|
          @current_building.tiles.times do |tile_y|
            placement_tx = @placement_tx + tile_x
            placement_ty = @placement_ty + tile_y
            x = placement_tx * @map.tile_size
            y = placement_ty * @map.tile_size
            placement_valid = @map.can_place?(placement_tx, placement_ty, 1, 1, @enemies)
            @current_building_background << @camera.to_screen_space!({
              x: x, y: y, w: @map.tile_size, h: @map.tile_size,
              path: :pixel,
              r: placement_valid ? 0 : 255,
              g: placement_valid ? 255 : 0,
              b: 0, a: 64
            })
          end
        end
      else
        @current_building_background = nil
      end

    end

    def render(args)
      map_png = {
        x: 0,
        y: 0,
        w: (2560 * (@tile_size / 16).floor).floor,
        h: (2560 * (@tile_size / 16).floor).floor,
        source_x: 0,
        source_y: 0,
        source_w: 2560,
        source_h: 2560,
        path: "data/maps/dragonmaul/simplified/level_0/int_grid.png"
      }
      screen_renderables = [map_png].map do |c|
        @camera.to_screen_space(c)
      end
      # size = @map.chunk_px
      # screen_renderables = @map.chunks_in_viewport(@camera).map do |c|
      #   @map.ensure_chunk_rendered(args, c.cx, c.cy)
      #   sprite = { x: c.cx * size, y: c.cy * size, w: size, h: size, path: @map.rt_name(c.cx, c.cy) }

      #   @camera.to_screen_space!(sprite)

      #   if @debug
      #     @debug_renderables.concat(SpriteKit::Primitives.borders(
      #       {
      #         x: sprite.x,
      #         y: sprite.y,
      #         w: sprite.w,
      #         h: sprite.h,
      #       },
      #       color: { r: 0, g: 255, b: 255, a: 200 }
      #     ).values)
      #   end
      #   sprite
      # end

      # in render, alongside the chunk sprites
      building_sprites = @map.buildings_in_viewport(@camera).map do |b|
        sprite = b.dup
        @camera.to_screen_space!(sprite)
        sprite
      end

      grid = []
      if @show_grid
        grid = render_grid(region: @camera.to_world_space!(@camera.viewport.dup))

        size_px = 20 * @camera.scale
        grid.concat(@map.tiles_in_viewport(@camera).map do |t|
          @camera.to_screen_space!({
            x: t.x,
            y: t.y,
            text: @graph.flow[@map.chunk_key((t.x / @map.tile_size).floor, (t.y / @map.tile_size).floor)],
            size_px: size_px,
            anchor_x: 0,
            anchor_y: 0,
            r: 50,
            g: 50,
            b: 50,
            a: 255,
          })
        end)

      end

      if @debug
        if @debug_solve_tile
          start = { x: @debug_solve_tile.x, y: @debug_solve_tile.y, cost: 0 }
          solved_path = [start].concat(@graph.solve_path(@debug_solve_tile))
          # idx = 0
          # prev_tile = nil
          # debug_path = Array.map(solved_path) do |tile|
          #   w = @map.tile_size
          #   h = @map.tile_size
          #   x = tile.x * @map.tile_size #+ (w / 2)
          #   y = tile.y * @map.tile_size #+ (h / 2)
          #   curr_tile = @camera.to_screen_space!(tile.merge!({
          #     w: w,
          #     h: h,
          #     y: y,
          #     x: x,
          #     r: 0,
          #     g: 255,
          #     b: 0,
          #     a: 255,
          #     path: :pixel
          #   }))

          #   angle = 0
          #   if prev_tile
          #     angle = Geometry.angle_from(prev_tile, curr_tile)
          #   end
          #   curr_tile.angle = angle
          #   idx += 1
          #   prev_tile = curr_tile
          #   curr_tile
          # end
          line_thickness = 4

          # transform tiles to screen space (same as before)
          screen_tiles = solved_path.map do |tile|
            ts = @map.tile_size
            @camera.to_screen_space!(tile.merge({
              w: ts, h: ts,
              x: tile.x * ts,
              y: tile.y * ts
            }))
          end

          # center point of each tile
          points = screen_tiles.map { |t| { x: t.x + t.w / 2, y: t.y + t.h / 2 } }

          # one rotated pixel-sprite per segment
          debug_path = points.each_cons(2).map do |a, b|
            dx = b.x - a.x
            dy = b.y - a.y
            length = Math.sqrt(dx * dx + dy * dy)

            {
              x: a.x,
              y: a.y - line_thickness / 2,
              w: length,
              h: line_thickness,
              path: :pixel,
              angle: Math.atan2(dy, dx).to_degrees,
              angle_anchor_x: 0,
              angle_anchor_y: 0.5,
              r: 0, g: 255, b: 0, a: 255
            }
          end

          @debug_renderables.concat(debug_path)
        end
      end

      enemies = []
      enemies_to_delete = []
      Array.each(@enemies) do |e|
        e.state = :walking

        advance_enemy(e)

        if Geometry.intersect_rect?(@map.goal, e)
          enemies_to_delete << e
        end

        e.update
        prefab = e.prefab
        prefab = [prefab] unless prefab.is_a?(Array)
        Array.each(prefab) { |spr| enemies << @camera.to_screen_space!(spr.dup) }
      end


      if enemies_to_delete.length > 0
        @enemies = @enemies - enemies_to_delete
      end

      screen_renderables
        .concat(@debug_renderables)
        .concat(grid)
        .concat(building_sprites)
        .concat(enemies)
        .concat(@current_building_background || [])
        .concat([@current_building])

      args.outputs.primitives.concat(screen_renderables)

      args.outputs.primitives.concat([
        @camera.viewport,
      ]).concat(@buttons.values)

      args.outputs.primitives << DR.current_framerate_primitives
    end


    def handle_input
      inputs = @inputs

      speed = ((500 / @camera.scale) / 100) * (FPS / 45) # * 10

      pan_up    = inputs.up
      pan_down  = inputs.down
      pan_right = inputs.right
      pan_left  = inputs.left

      camera_panning_enabled = false
      if camera_panning_enabled
        edge = 12 # px from screen border
        mx = inputs.mouse.x
        my = inputs.mouse.y

        pan_up    ||= my >= Grid.h - edge
        pan_down  ||= my <= edge
        pan_right ||= mx >= Grid.w - edge
        pan_left  ||= mx <= edge
      end

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

      if inputs.keyboard.escape
        @debug_solve_tile = nil
        @current_building = nil
        @placement_valid = nil
      end

      if inputs.mouse.click
        clicked_button = Geometry.find_intersect_rect(inputs.mouse, @buttons.values)

        if clicked_button
          clicked_button.on_click.call(inputs.mouse)
        elsif @current_building && @placement_valid
          @map.place_building!(@current_building, tile_x: @placement_tx, tile_y: @placement_ty)
          @graph.compute(@map.goal_tile)
          # keep placing if shift held (classic TD UX), else exit placement mode
          @current_building = nil unless @inputs.keyboard.shift
        elsif @debug && (clicked_tile = Geometry.find_intersect_rect(@world_mouse, @map.tiles_in_viewport(@camera)))
          @debug_solve_tile = clicked_tile.tap do |t|
            t.x = (t.x / @map.tile_size).floor
            t.y = (t.y / @map.tile_size).floor
            t.w = (t.w / @map.tile_size).floor
            t.h = (t.h / @map.tile_size).floor
          end
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
        @camera.target_scale = @zoom[:default]
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

    def render_grid(camera: @camera, region:, w: @tile_size, h: @tile_size, show_blocked: false)
      min_x = (region.x / w).floor * w
      min_y = (region.y / h).floor * h
      max_x = ((region.x + region.w) / w).ceil * w
      max_y = ((region.y + region.h) / h).ceil * h

      solids = []

      x = min_x
      while x <= max_x
        s = { x: x, y: min_y, w: 1, h: max_y - min_y }
        camera.to_screen_space!(s)
        solids << s.merge!({ w: 1, **PALETTE.white, path: :solid })
        x += w
      end

      y = min_y
      while y <= max_y
        s = { x: min_x, y: y, w: max_x - min_x, h: 1 }
        camera.to_screen_space!(s)
        solids << s.merge!({ h: 1, **PALETTE.white, path: :solid })
        y += h
      end

      # if show_blocked
      #   tx  = (min_x / w).to_i
      #   ty  = (min_y / h).to_i
      #   cols = ((max_x - min_x) / w).to_i
      #   rows = ((max_y - min_y) / h).to_i
      #   rows.times do |row|
      #     x = tx + row
      #     cols.times do |col|
      #       y = ty + col
      #       next if !@map.occupied?(x, y)
      #       solids << {
      #         x: x * w,
      #         y: y * h,
      #         w: w,
      #         h: h,
      #         **PALETTE.blocked_tile,
      #         path: :pixel,
      #       }
      #     end
      #   end
      # end
      #
      #
      if show_blocked
        col_start  = (min_x / w).to_i
        row_start  = (min_y / h).to_i
        cols = ((max_x - min_x) / w).to_i
        rows = ((max_y - min_y) / h).to_i

        cols.times do |col|
          col = col_start + col
          rows.times do |row|
            row = row_start + row
            next unless @map.occupied?(col, row)
            solids << camera.to_screen_space!({
              x: col * w, y: row * h, w: w, h: h,
              **PALETTE.blocked_tile, path: :pixel,
            })
          end
        end
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
      ts = @map.tile_size
      current_tile = { x: (e.x / ts).floor, y: (e.y / ts).floor }

      step = @graph.next_step(current_tile)
      if step
        e.state = :walking
        move_toward(e, (step.x + 0.5) * ts, (step.y + 0.5) * ts)
        return
      end

      surrounding_tiles = Graph::NEIGHBORS_AND_DIAGONALS

      tower_nearby = nil

      center_of_tile = {
        x: ((e.x + e.w / 2) / ts).floor,
        y: ((e.y + e.h / 2) / ts).floor,
      }
      surrounding_tiles.each do |dx, dy|
        tower_nearby = @map.occupied[@map.chunk_key(center_of_tile.x + dx, center_of_tile.y + dy)]
        break if tower_nearby
      end

      if tower_nearby
        if !e.out_of_range?(tower_nearby)
          e.state = :attacking
          attack_tower(e, tower_nearby)
        else
          e.state = :walking
          move_toward(e, tower_nearby.x + tower_nearby.w / 2, tower_nearby.y + tower_nearby.h / 2)
        end
        return
      end

      # blocked: follow the wall-ignoring flow toward the goal
      step = @graph.attack_next_step(current_tile, e.seg)
      unless step
        e.state = :idle
        return
      end

      e.state = :walking
      move_toward(e, (step.x + 0.5) * ts, (step.y + 0.5) * ts)
    end

    def move_toward(e, tx, ty)
      dx = tx - e.x
      dy = ty - e.y
      dist = Math.sqrt(dx * dx + dy * dy)
      return if dist.zero?

      s = enemy_step(e)
      if dist <= s
        e.x = tx * 0.7
        e.y = ty * 0.7                     # snap so floor() actually advances
      else
        e.x += (dx / dist) * s
        e.y += (dy / dist) * s
      end
      e.target_x = e.x
      e.target_y = e.y

      e.direction = dx.abs > dy.abs ? (dx > 0 ? :right : :left) : (dy > 0 ? :up : :down)
    end

    def enemy_step(e)
      (e.speed || 150) / 100.0
    end

    def attack_tower(e, tower)
      damage = e.attack(tower)

      if damage && @map.damage_building!(tower, damage)
        # wall breached: refresh both flows
        @graph.compute(@map.goal_tile)
      end
    end

    def __debug_x_movement
      open_right = false
      @map.w.times do |x|
        @map.h.times do |y|

          if !(x >= 0 && x < @map.w && y > @map.h - 20 && y < @map.h - 10)
            next
          end
          if x % 2 == 0 && y % 4 == 0
            open_right = y if !open_right

            building = SPRITES.cannon.dup

            if open_right == y && x >= @map.w - 2
              next
            elsif open_right != y && x < 2
              # open_right = !open_right
              next
            end

            @map.place_building!(building, tile_x: x, tile_y: y)
          end
        end
      end
    end

    def __debug_y_movement
      if !(x >= 0 && x < @map.w && y > @map.h - 20 && y < @map.h - 10)
        next
      end

      if x % 2 == 0 && y % 4 == 0
        open_right = y if !open_right

        building = SPRITES.cannon.dup

        if open_right == y && x >= @map.w - 2
          next
        elsif open_right != y && x < 2
          # open_right = !open_right
          next
        end

        @map.place_building!(building, tile_x: x, tile_y: y)
      end
    end
  end
end
