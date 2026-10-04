# Where monitors.yml files are read from (ADR 0016). Managed on the settings
# page; saving or syncing reads the files straight away.
class SourcesController < ApplicationController
  def create
    @source = Uptime::Source.new(source_params)
    save_and_sync "Source added."
  end

  def update
    @source = Uptime::Source.find(params[:id])
    @source.assign_attributes(source_params)
    save_and_sync "Source saved."
  end

  def sync
    source = Uptime::Source.find(params[:id])
    source.sync!
    redirect_to settings_path, notice: "#{source.name} synced."
  end

  private
    def source_params
      params.expect(uptime_source: %i[ name path ])
    end

    def save_and_sync(notice)
      if @source.save
        @source.sync!
        redirect_to settings_path, notice: notice
      else
        @provider = OidcProvider.current || OidcProvider.new(name: "Clinch")
        render "settings/show", status: :unprocessable_content
      end
    end
end
