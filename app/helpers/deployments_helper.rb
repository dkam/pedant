module DeploymentsHelper
  # An image reference with its digest cut short. The tag says which version,
  # and the whole reference is in the title.
  def image_reference(service)
    return tag.span("built here, not pulled", class: "text-faint") unless service.image

    name, digest = service.image.split("@", 2)
    shown = digest ? "#{name}@#{digest.first(19)}…" : name
    reference = tag.code(shown, class: "font-mono text-xs", title: service.image)
    service.resolved ? reference : safe_join([ reference, tag.span("as written", class: "ml-1 text-xs text-warn") ], " ")
  end

  def folder(working_dir) = working_dir == "." ? "the top of the repo" : "#{working_dir}/"
end
