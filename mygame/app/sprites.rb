module App
  SPRITES = {
    cannon: {
      source_x: 8,
      source_y: 8,
      source_h: 32,
      source_w: 32,
      path: "sprites/craftpix/1_main_character/2_weapons/3.png",
      animations: []
    },
    ground: {
      source_x: 278,
      source_y: 662,
      source_h: 82,
      source_w: 82,
      path: "sprites/craftpix/4_gui/2_buttons/button_set.png",
      # source_x: 0,
      # source_y: 0,
      # source_h: 1024,
      # source_w: 1024,
      # path: "sprites/grass_tile.png",
    },
    wall: {
    },
    goblin: {
      speed: 100,
      animations: {
        idle: {
          source_x: 8,
          source_y: 8,
          source_h: 32,
          source_w: 32,
          path: "sprites/craftpix/3_enemies/1/run_sd.png",
          hold_for: 1,
          repeat: true
        },
        walking: {
          repeat: true,
          frames: [
            {
              source_x: 8,
              source_y: 8,
              source_h: 32,
              source_w: 32,
              path: "sprites/craftpix/3_enemies/1/run_sd.png",
              hold_for: 8
            },
            {
              source_x: 56,
              source_y: 8,
              source_h: 32,
              source_w: 32,
              path: "sprites/craftpix/3_enemies/1/run_sd.png",
              hold_for: 8
            },
            {
              source_x: 104,
              source_y: 8,
              source_h: 32,
              source_w: 32,
              path: "sprites/craftpix/3_enemies/1/run_sd.png",
              hold_for: 8,
            },
            {
              source_x: 200,
              source_y: 8,
              source_h: 32,
              source_w: 32,
              path: "sprites/craftpix/3_enemies/1/run_sd.png",
              hold_for: 8,
            },
            {
              source_x: 200,
              source_y: 8,
              source_h: 32,
              source_w: 32,
              path: "sprites/craftpix/3_enemies/1/run_sd.png",
              hold_for: 8
            }
          ]
        },
      }
    }
  }

  # Build directional animations, use this later.
  9.times do |i|
    offset_x = 8
    column_gap = 16
    cannon = SPRITES.cannon
    SPRITES.cannon.animations[i] = {
      source_x: offset_x + (i * column_gap),
      source_y: cannon.source_y,
      source_w: cannon.source_w,
      source_h: cannon.source_h,
      path: cannon.path
    }
  end
end
