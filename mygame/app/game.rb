module App
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
end
