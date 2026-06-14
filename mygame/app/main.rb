FPS = 60

require "vendor/sprite_kit/sprite_kit.rb"
require "app/animation_mixin.rb"
require "app/character.rb"
require "app/enemy.rb"
require "app/sprites.rb"
require "app/map.rb"
require "app/play_scene.rb"
require "app/game.rb"

module Main
  attr_accessor :game

  def tick(args)
    @game ||= App::Game.new
    @game.tick(args)
  end

  def reset(args)
    @game = nil
  end
end
