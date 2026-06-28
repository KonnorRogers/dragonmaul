module App
  class Graph
    NEIGHBORS = [
      [0, 1],  # right
      [0, -1], # left
      [1, 0],  # up
      [-1, 0]  # down
    ]
    DIAGONALS = [
      [1, 1], # right-up
      [1, -1], # right-down
      [-1, 1], # left-up
      [-1, -1] # left-down
    ]

    NEIGHBORS_AND_DIAGONALS = NEIGHBORS + DIAGONALS

    attr_accessor :flows

    def initialize(map:, waypoints:, goal:)
      @map = map
      @flows = nil
      @stages = []

      @goal = goal
      sorted_stages = waypoints
                .group_by { |wp| wp[:order] || 1 }
                .sort_by  { |order, _| order }
                .map      { |_, group| group }
      @stages = sorted_stages + [[goal]]
      @unobstructed ||= @stages.map { |goals| build_flow(goals: goals, ignore_occupied: true) }
      @last_segment = @stages.length - 1
      recompute
    end

    def recompute(fiber: false)
      # call THIS on tower placement / wall breach, not full compute
      flows = @stages.each_with_index.map do |goals, i|
        {
          goals:             goals,
          flow:              build_flow(goals: goals, ignore_occupied: false),
          unobstructed_flow: @unobstructed[i],
        }
      end
      @flows = flows
    end

    # which stage does a freshly spawned enemy start heading toward?
    # nearest goal of stage 0 decides nothing here — the enemy always starts at
    # stage 0; this just returns 0. keep it explicit in case you later spawn
    # enemies mid-route.
    def initial_segment(_current_tile) = 0

    def nearest_goal(tile, seg)
      @flows[seg][:goals].min_by { |g| (g.x - tile.x)**2 + (g.y - tile.y)**2 }
    end

    def reached_stage?(tile, seg)
      @flows[seg][:goals].any? { |g| g.x == tile.x && g.y == tile.y }
    end

    WAYPOINT_RADIUS = 14   # path-cost units (~1 diagonal tile); bump to 20 for an earlier turn

    # close enough by path distance to count as reaching this stage
    def near_stage?(tile, seg)
      cost = @flows[seg][:flow][@map.chunk_key(tile.x, tile.y)]
      return cost <= WAYPOINT_RADIUS if cost
      # tile not covered by this stage's field (walled off mid-route) —
      # fall back to straight-line proximity so we can still advance
      g = nearest_goal(tile, seg)
      ((g.x - tile.x).abs + (g.y - tile.y).abs) <= 1
    end

    # exactly on a goal of this stage (used only to stop stepping at the final goal)
    def on_stage_goal?(tile, seg)
      @flows[seg][:goals].any? { |g| g.x == tile.x && g.y == tile.y }
    end

    def advance_segment(tile, seg)
      return seg if seg >= @last_segment
      near_stage?(tile, seg) ? seg + 1 : seg
    end

    def next_step(current_tile, seg, attack: false)
      field = @flows[seg]
      return nil unless field
      return nil if on_stage_goal?(current_tile, seg) && seg >= @last_segment

      flow = attack ? field[:unobstructed_flow] : field[:flow]
      best = best_neighbor(current_tile, flow)
      # obstructed field doesn't reach here (wall cut us off) — fall back to the
      # wall-ignoring field so we still move toward the goal instead of freezing
      best ||= best_neighbor(current_tile, field[:unobstructed_flow]) unless attack
      best
    end

    def best_neighbor(current_tile, flow)
      best = nil
      NEIGHBORS_AND_DIAGONALS.each do |dx, dy|
        x = current_tile.x + dx
        y = current_tile.y + dy
        cost = flow[@map.chunk_key(x, y)]
        next unless cost
        best = { x: x, y: y, cost: cost } if best.nil? || cost < best[:cost]
      end
      best
    end

    def attack_next_step(current_tile, seg)
      next_step(current_tile, seg, attack: true)
    end

    def add_to_frontier(flow:, frontier:, cost:, x:, y:, ignore_occupied:)
      key = @map.chunk_key(x, y)
      return if !@map.tiles.key?(key)
      return if flow.key?(key)
      return if !ignore_occupied && @map.occupied?(x, y)
      flow[key] = cost
      frontier << { x: x, y: y }
    end
    def build_flow(goals:, ignore_occupied:)
      flow = {}
      frontier = []
      goals.each { |g| flow[@map.chunk_key(g.x, g.y)] = 0; frontier << g }
      head = 0
      visits = 0
      while head < frontier.length
        current = frontier[head]; head += 1
        visits += 1
        dist = flow[@map.chunk_key(current.x, current.y)]
        NEIGHBORS_AND_DIAGONALS.each do |dx, dy|
          add_to_frontier(flow: flow, frontier: frontier, cost: dist + 10, x: current.x + dx, y: current.y + dy, ignore_occupied: ignore_occupied)
        end
      end
      puts "  one flood: visits=#{visits} frontier.len=#{frontier.length}"
      flow
    end

    # def build_flow(goals:, ignore_occupied:)
    #   flow = {}
    #   frontier = []
    #   goals.each do |g|
    #     flow[@map.chunk_key(g.x, g.y)] = 0
    #     frontier << g
    #   end
    #   head = 0
    #   while head < frontier.length
    #     current = frontier[head]
    #     head += 1
    #     dist = flow[@map.chunk_key(current.x, current.y)]
    #     NEIGHBORS.each { |dx, dy| add_to_frontier(flow: flow, frontier: frontier, cost: dist + 10, x: current.x + dx, y: current.y + dy, ignore_occupied: ignore_occupied) }
    #     DIAGONALS.each { |dx, dy| add_to_frontier(flow: flow, frontier: frontier, cost: dist + 14, x: current.x + dx, y: current.y + dy, ignore_occupied: ignore_occupied) }
    #   end
    #   flow
    # end

    # debug: walk a tile through every remaining stage to the goal
    def solve_path(current_tile, seg: 0)
      path = []
      from = current_tile
      s = seg
      guard = 0
      loop do
        break if (guard += 1) > 10_000
        if reached_stage?(from, s)
          break if s >= @last_segment
          s += 1
          next
        end
        nxt = next_step(from, s)
        break if nxt.nil?
        path << nxt
        from = nxt
      end
      path
    end
  end
end
