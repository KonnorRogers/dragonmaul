module App
  class Character < SpriteKit::Sprite
    attr_accessor :target_x, :target_y, :target, :engine,
                  :speed, :animations, :hit_box, :state, :direction, :collision, :entity,
                  :type, :id, :current_hp, :max_hp, :last_attack, :scale, :radius,
                  :attack_range, :attack_cooldown

    include AnimationMixin

    def initialize(engine:, **kwargs)
      super(**kwargs)

      @engine = engine
      @state = :idle
      # @health_bar = {
      #   background: App::UI::Bar.new(type: :enemy, a: 64),
      #   outline: App::UI::Bar.new(type: :outline),
      #   fill: App::UI::Bar.new(type: :enemy),
      #   label: {
      #     anchor_x: 0.5,
      #     anchor_y: 0.5,
      #     r: 255,
      #     g: 255,
      #     b: 255,
      #     x: @x,
      #     y: @y,
      #     text: "",
      #   }
      # }

      @max_hp = kwargs.max_hp || 100
      @current_hp = kwargs.current_hp || @max_hp
      @attack_cooldown = kwargs.attack_cooldown || 2
      @attack_range = kwargs.attack_range || @w * 2
      @last_attack = kwargs.last_attack || 0
      @collision = kwargs.collision
      @target_x = kwargs.target_x || kwargs.x || 0
      @target_y = kwargs.target_y || kwargs.y || 0
    end

    def serialize
      hash = super

      hash.delete(:engine)
      hash
    end

    def prefab
      ary = []

      if @animation_prefab
        ary.concat(@animation_prefab)
      else
        ary << self
      end

      # @health_bar.each do |k, v|
      #   if k == :label
      #     ary << v
      #   else
      #     ary << v.prefab
      #   end
      # end
      ary
    end

    def health_bar
      @health_bar
    end

    def update
      update_sprite
      update_health_bar
    end

    def calc_attack
      min = 1
      max = 10
      (rand * max).clamp(min, max).round
    end

    def update_health_bar
      return if !@health_bar
      return if !@x || !@y || !@w || !@h

      height = 16
      padding = 0
      width = 64
      x = @x - (width / 2) + (@w / 2)
      y = @y + @h + padding
      @health_bar.each do |key, primitive|
        primitive.x = x
        primitive.y = y
        if key == :label
          primitive.size_px = 12
          # primitive.anchor_y = 0.5
          primitive.y = y + (height / 2)
          primitive.x = x + (width / 2)
          primitive.text = "#{@current_hp} / #{@max_hp}"
        else
          primitive.w = width
          primitive.h = height
          primitive.update
        end
      end
      @health_bar.fill.w = (hp_percentage * width).round
    end

    def hp_percentage
      @current_hp / @max_hp
    end

    def attack_on_cooldown?
      @last_attack + (@attack_cooldown * FPS) > @engine.tick_count
    end

    def out_of_range?(target)
      distance_from(target) > @attack_range
    end

    def distance_from(target)
      Geometry.distance(self, target)
    end

    def attack(target)
      return nil if attack_on_cooldown?
      return nil if out_of_range?(target)

      @last_attack = @engine.tick_count
      damage = calc_attack

      # if target
      #   @engine.floating_text.add(damage, anchor: target, **{r: 0, b: 0, g: 0, a: 255})
      #   target.take_damage(damage)
      # end

      damage
    end

    def take_damage(damage)
      @current_hp -= damage

      if @current_hp < 0
        @current_hp = 0
      end
    end
  end
end
