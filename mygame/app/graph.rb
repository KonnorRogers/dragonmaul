module App
  class Graph
    ARRAY_FILL = -1
    STEPS = [
      # [dx, dy, cost]
      # Cardinal Directions
      [0, 1, 10], [0, -1, 10], [1, 0, 10], [-1, 0, 10],
      # Diagonal Directions
      [1, 1, 14], [1, -1, 14], [-1, 1, 14], [-1, -1, 14]
    ].freeze

    attr_accessor :flows

    def initialize(map:, waypoints:, goal:)
      @map = map
      @flows = nil
      @stages = []

      @goal = goal
      sorted_stages = waypoints
                .group_by { |wp| wp[:order] || 0 }
                .sort_by  { |order, _| order }
                .map      { |_, group| group }
      @stages = sorted_stages + [[goal]]
      @unobstructed ||= @stages.map { |goals| build_flow(goals: goals, ignore_occupied: true) }
      @flow_buffers = @stages.map { Array.new(@map.w * @map.h, ARRAY_FILL) }   # one scratch buffer per stage
      @flow_buffers_back = @stages.map { Array.new(@map.w * @map.h, ARRAY_FILL) }
      @last_segment = @stages.length - 1
      @recomputing = false
      @recompute_queue = []
      recompute
    end

    def recompute
      # call THIS on tower placement / wall breach, not full compute
      flows = @stages.each_with_index.map do |goals, i|
        {
          goals:             goals,
          flow:              build_flow!(@flow_buffers[i], goals: goals, ignore_occupied: false),
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

    def near_stage?(tile, seg)
      cost = at(@flows[seg][:flow], tile.x, tile.y)
      return cost <= WAYPOINT_RADIUS if cost
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
      STEPS.each do |dx, dy, _cost|
        x = current_tile.x + dx
        y = current_tile.y + dy
        cost = at(flow, x, y)
        next unless cost
        best = { x: x, y: y, cost: cost } if best.nil? || cost < best[:cost]
      end
      best
    end

    def attack_next_step(current_tile, seg)
      next_step(current_tile, seg, attack: true)
    end
    # allocating version — used once for the cached unobstructed fields
    def build_flow(goals:, ignore_occupied:)
      build_flow!(Array.new(@map.w * @map.h, ARRAY_FILL), goals: goals, ignore_occupied: ignore_occupied)
    end

    # reusing version — used every recompute for the obstructed fields
    # This is a very _tight_ method that has already been refactored from 200ms down to 50ms. There's probably more ways to make it faster, but this is goood for now.
    def build_flow!(flow, goals:, ignore_occupied:)
      w = @map.w.to_i
      h = @map.h.to_i

      # clear the buffer in place (mruby Array#fill(nil) rejects this form)
      # i = 0
      # n = flow.length
      # while i < n
      #   flow[i] = nil
      #   i += 1
      # end
      flow.fill(ARRAY_FILL)

      ground = @map.ground_bits
      blocked = @map.occupied_bits
      frontier = []
      goals.each do |g|
        idx = g.y.to_i * w + g.x.to_i
        flow[idx] = 0
        frontier << idx
      end

      head = 0
      while head < frontier.length
        idx = frontier[head]
        head += 1
        cx = idx % w
        cy = idx.idiv(w)
        dist = flow[idx]
        si = 0
        while si < 8
          s = STEPS[si]
          si += 1
          x = cx + s[0]
          y = cy + s[1]

          next if x < 0 || y < 0 || x >= w || y >= h

          nidx = y * w + x
          next unless ground[nidx]

          next if flow[nidx] != ARRAY_FILL
          next if !ignore_occupied && blocked[nidx]

          flow[nidx] = dist + s[2]
          frontier << nidx
        end
      end
      flow
    end

    def at(flow, x, y)
      return nil if x < 0 || y < 0 || x >= @map.w || y >= @map.h

      v = flow[y * @map.w + x]

      return nil if v == ARRAY_FILL

      v
    end

    def cost_at(seg, x, y)
      at(@flows[seg][:flow], x, y)
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
    # kick off a sliced recompute (call on tower placed / wall breached)
    def begin_recompute
      @recompute_queue = (0...@stages.length).to_a
      @recomputing = true
    end

    def recomputing?
      !!@recomputing
    end

    # advance one stage per call; publish + swap when all stages are rebuilt.
    # floods into the BACK buffers so enemies keep reading the live ones.
    def step_recompute
      return unless @recomputing
      i = @recompute_queue.shift
      build_flow!(@flow_buffers_back[i], goals: @stages[i], ignore_occupied: false)
      if @recompute_queue.empty?
        @flow_buffers, @flow_buffers_back = @flow_buffers_back, @flow_buffers
        @flows = @stages.each_with_index.map do |goals, j|
          { goals: goals, flow: @flow_buffers[j], unobstructed_flow: @unobstructed[j] }
        end
        @recomputing = false
      end
    end
  end
end
