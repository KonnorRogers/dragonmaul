module App
  class Enemy < Character
    attr_accessor :segment

    def move()
      # return if moving?(e)              # already sliding — ignore input

      # ncol, nrow = e.col + dir.dx, e.row + dir.dy
      # return if @maze[nrow][ncol] == WALL   # <-- collision = one array lookup

      # e.col, e.row = ncol, nrow              # commit the logical move now
      # e.target_x = ncol * TILE + TILE/2      # target = the NEW cell's center
      # e.target_y = nrow * TILE + TILE/2
    end

    # attr_accessor :home_x, :home_y, :ai_state, :aggro_range, :max_roam

    # def initialize(...)
    #   super(...)
    #   @wander_target_x = @x
    #   @wander_target_y = @y
    #   @home_x = @x
    #   @home_y = @y
    #   @wander_wait = rand(60)
    #   pick_wander_target
    #   @ai_state = :wandering
    #   @aggro_range = 100
    #   @max_roam = 300
    # end

    # def self.serialize(**kwargs)
    #   {
    #     id: kwargs.id,
    #     type: kwargs.type,
    #     max_hp: kwargs.max_hp,
    #     current_hp: kwargs.current_hp,
    #     x: kwargs.x,
    #     y: kwargs.y,
    #     home_x: kwargs.home_x,
    #     home_y: kwargs.home_y,
    #   }
    # end

    # def serialize
    #   {
    #     id: @id,
    #     type: @type,
    #     max_hp: @max_hp,
    #     current_hp: @current_hp,
    #     x: @x,
    #     y: @y,
    #     home_x: @home_x,
    #     home_y: @home_y,
    #   }
    # end

    # def prefab
    #   h = 0
    #   h = 20 if @h < 100
    #   ary = [
    #     self,
    #   ]

    #   if @engine.debug
    #     ary << { x: @x + (@w / 2), y: @y + @h + h, text: @ai_state.to_s, anchor_x: 0.5, r: 255, b: 255, g: 255, a: 255 }
    #   end

    #   ary
    # end

    # def update
    #   super
    #   update_state
    # end

    # def update_state
    #   player = @engine.player
    #   dist_to_player = Geometry.distance(player, self)

    #   dist_to_home = Geometry.distance({ x: @home_x, y: @home_y }, self)

    #   case @ai_state
    #   when :wandering
    #     tick_wander
    #     @ai_state = :chasing if dist_to_player < @aggro_range
    #   when :chasing
    #     tick_chase
    #     if dist_to_player > @aggro_range * 2 || dist_to_home > @max_roam
    #       @ai_state = :returning
    #     end
    #   when :returning
    #     tick_return

    #     if dist_to_home < 8
    #       @ai_state = :wandering
    #     end
    #   end
    # end

    # def pick_wander_target
    #   angle = rand * 360
    #   dist  = 50 + rand(100)  # wander 50-150px from current pos
    #   @wander_target_x = @x + Math.cos(angle * Math::PI / 180) * dist
    #   @wander_target_y = @y + Math.sin(angle * Math::PI / 180) * dist
    # end

    # def tick_wander
    #   return tick_wait if @wander_wait > 0

    #   dx = @wander_target_x - @x
    #   dy = @wander_target_y - @y
    #   dist = Math.sqrt(dx * dx + dy * dy)

    #   if dist < 4
    #     # Reached target — wait a moment then pick a new one
    #     @wander_wait = 60 + rand(120)  # 1-3 seconds at 60fps
    #     pick_wander_target
    #   else
    #     speed = 0.6
    #     @x += (dx / dist) * speed
    #     @y += (dy / dist) * speed
    #   end
    # end

    # def tick_wait
    #   @wander_wait -= 1
    # end

    # def tick_chase
    #   player = @engine.player
    #   dx = player.x - @x
    #   dy = player.y - @y
    #   dist = Math.sqrt(dx * dx + dy * dy)

    #   if dist < @attack_range
    #     attack(player)
    #   else
    #     speed = 1.2
    #     @x += (dx / dist) * speed
    #     @y += (dy / dist) * speed
    #   end
    # end

    # def tick_return
    #   dx = @home_x - @x
    #   dy = @home_y - @y
    #   dist = Math.sqrt(dx * dx + dy * dy)
    #   return if dist < 4
    #   speed = 1.0
    #   @x += (dx / dist) * speed
    #   @y += (dy / dist) * speed
    # end
  end
end
