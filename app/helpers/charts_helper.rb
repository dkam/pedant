# Small line charts drawn as SVG on the server: no JavaScript, no chart
# library. Each says what it measures and in which unit, which is what Kuma's
# push graphs couldn't (they called everything ms).
module ChartsHelper
  WIDTH = 300
  HEIGHT = 64

  # values: oldest first. limits: [[number, "warn" | "down"], ...], drawn as
  # dashed lines. format: how to show a number with its unit.
  def line_chart(values, kind:, title:, limits: [], format: ->(number) { number.to_s })
    values = values.compact
    return if values.empty?

    low, high = (values + limits.map(&:first)).minmax
    span = (high - low).nonzero? || 1
    y = ->(number) { (HEIGHT - 4 - (number - low) / span * (HEIGHT - 8)).round(1) }
    x = ->(index) { values.size == 1 ? WIDTH / 2 : (index * WIDTH.to_f / (values.size - 1)).round(1) }

    tag.figure(data: { chart: kind }, class: "rounded-lg border border-stone-200 bg-white p-4") do
      safe_join([
        tag.figcaption(class: "flex items-baseline justify-between text-sm") do
          safe_join([
            tag.span(title, class: "font-medium"),
            tag.span("latest #{format.(values.last)} · range #{format.(values.min)} to #{format.(values.max)}", class: "text-xs text-stone-500")
          ])
        end,
        tag.svg(viewBox: "0 0 #{WIDTH} #{HEIGHT}", preserveAspectRatio: "none", class: "mt-2 h-16 w-full", role: "img", "aria-label": title) do
          lines = limits.map do |limit, level|
            tag.line(x1: 0, x2: WIDTH, y1: y.(limit), y2: y.(limit), "stroke-dasharray": "4 3", "stroke-width": 1,
              class: level == "down" ? "stroke-red-400" : "stroke-amber-400")
          end
          points = values.each_with_index.map { |value, index| "#{x.(index)},#{y.(value)}" }.join(" ")
          safe_join(lines + [ tag.polyline(points: points, fill: "none", "stroke-width": 1.5, class: "stroke-stone-700", "vector-effect": "non-scaling-stroke") ])
        end
      ])
    end
  end

  # Run times in seconds, or minutes once they're long.
  def duration_chart(durations_ms)
    durations = durations_ms.compact
    return if durations.empty?

    minutes = durations.max > 120_000
    values = durations.map { |ms| (ms / (minutes ? 60_000.0 : 1000.0)).round(1) }
    unit = minutes ? "min" : "s"
    line_chart(values, kind: "duration", title: "Run time (#{unit})", format: ->(number) { "#{number % 1 == 0 ? number.to_i : number} #{unit}" })
  end
end
