module App
  class Graph
    NEIGHBORS = [
      [0, 1], # up
      [0, -1], # down
      [1, 0], # left
      [-1, 0] # right
    ]

    DIAGONALS = [
      [1, 1], # right-up
      [1, -1], # down-right
      [-1, 1], # left-up
      [-1, -1], # left-down
    ]

    NEIGHBORS_AND_DIAGONALS = NEIGHBORS + DIAGONALS

    attr_accessor :flow

    def initialize(map:)
      @map = map
      @flow = nil
      @unobstructed_flow = nil
      @goal = nil
    end

    def add_to_frontier(flow:, frontier:, cost:, x:, y:, ignore_occupied:)
      key = @map.chunk_key(x, y)

      # tile doesn't exist
      return if !@map.tiles.key?(key)

      # tile already computed
      return if flow.key?(key)

      if !ignore_occupied && @map.occupied?(x, y)
        return
      end

      flow[key] = cost
      frontier << { x: x, y: y }
    end

    # Super basic BFS for 8 way directions from a "goal"
    def compute(goal)
      @goal = goal

      @flow = build_flow(goal: goal, ignore_occupied: false)
      @unobstructed_flow = build_flow(goal: goal, ignore_occupied: true)
    end

    def build_flow(goal:, ignore_occupied:)
      flow = {}
      flow[@map.chunk_key(goal.x, goal.y)] = 0

      frontier = [goal]

      until frontier.empty?
        current_tile = frontier.shift
        current_distance = flow[@map.chunk_key(current_tile.x, current_tile.y)]

        NEIGHBORS.each do |dx, dy|
          x = current_tile.x + dx
          y = current_tile.y + dy
          add_to_frontier(x: x, y: y, frontier: frontier, cost: 10 + current_distance, flow: flow, ignore_occupied: ignore_occupied)
        end

        DIAGONALS.each do |dx, dy|
          x = current_tile.x + dx
          y = current_tile.y + dy
          add_to_frontier(x: x, y: y, frontier: frontier, cost: 14 + current_distance, flow: flow, ignore_occupied: ignore_occupied)
        end
      end

      flow
    end

    def next_step(current_tile, flow: @flow)
      next_tile = nil

      return next_tile if current_tile.x == @goal.x && current_tile.y == @goal.y

      NEIGHBORS_AND_DIAGONALS.each do |dx, dy|
        x = current_tile.x + dx
        y = current_tile.y + dy
        cost = flow[@map.chunk_key(x, y)]
        next if !cost

        if !next_tile || cost < next_tile.cost
          next_tile = { x: x, y: y, cost: cost }
        end
      end

      next_tile
    end

    def attack_next_step(current_tile)
      next_step(current_tile, flow: @unobstructed_flow)
    end

    def solve_path(current_tile)
      path = []

      from = current_tile

      loop do
        return path if from.x == @goal.x && from.y == @goal.y

        tile = next_step(from)

        break if tile.nil?

        path << tile

        from = tile
      end
      path
    end
  end
end
