FPS = 60

require "vendor/sprite_kit/sprite_kit.rb"
require "app/extended_geometry.rb"
require "app/animation_mixin.rb"
require "app/character.rb"
require "app/enemy.rb"
require "app/sprites.rb"
require "app/map.rb"
require "app/graph.rb"
require "app/play_scene.rb"
require "app/game.rb"

module Main
  attr_accessor :game

  def start
    DR.reset_sprites
  end

  def tick(args)
    if !@game
      DR.reset_sprites
      @game = App::Game.new
    end

    @game.tick(args)
  end

  def reset(args)
    @game = nil
  end
end

DR.reset
