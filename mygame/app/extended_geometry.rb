module App
  module ExtendedGeometry
    def self.point_in_cone?(rect1, rect2, aim_angle, cone_angle, range)
      hash = extended_distance_between(rect1, rect2)
      distance = hash[:distance]

      return false if distance > range

      dx = hash[:dx]
      dy = hash[:dy]

      point_angle = Math.atan2(dy, dx)
      diff = (point_angle - aim_angle) % (2 * Math::PI)
      diff -= 2 * Math::PI if diff > Math::PI

      diff.abs <= cone_angle / 2.0
    end

    def self.extended_distance_between(rect1, rect2)
      x1 = rect1.x
      y1 = rect1.y
      w1 = rect1.w
      h1 = rect1.h
      x2 = rect2.x
      y2 = rect2.y
      w2 = rect2.w
      h2 = rect2.h

      # find the closest point on each bounding box to the other
      closest_x1 = x1.clamp(x2, x2 + w2)
      closest_x2 = x2.clamp(x1, x1 + w1)
      closest_y1 = y1.clamp(y2, y2 + h2)
      closest_y2 = y2.clamp(y1, y1 + h1)

      dx = closest_x1 - closest_x2
      dy = closest_y1 - closest_y2

      distance = Math.sqrt(dx**2 + dy**2)

      {
        dx: dx,
        dy: dy,
        distance: distance
      }
    end

    def self.distance_between(rect1, rect2)
      extended_distance_between(rect1, rect2)[:distance]
    end

    def debug_triangle(triangle)
      [
        { x: triangle.x, y: triangle.y, text: "x: #{triangle.x}, y: #{triangle.y}" },
        { x: triangle.x2, y: triangle.y2, text: "x2: #{triangle.x2}, y2: #{triangle.y2}" },
        { x: triangle.x3, y: triangle.y3, text: "x3: #{triangle.x3}, y3: #{triangle.y3}" },
      ]
    end
  end
end
