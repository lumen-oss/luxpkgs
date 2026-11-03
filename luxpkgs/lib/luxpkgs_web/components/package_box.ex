defmodule LuxpkgsWeb.PackageBox do
  use LuxpkgsWeb, :html

  attr :name, :string, required: true
  attr :description, :string, default: ""
  attr :version, :string
  attr :download_count, :integer, default: 0

  def package(assigns) do
    ~H"""
    <.link
      navigate={~p"/package/#{@name}"}
      class="group h-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
    >
      <div class="h-full flex flex-col bg-base-100 border border-base-300 rounded-box hover:border-primary/40 transition-colors duration-200 p-6">
        <div class="space-y-4">
          <div class="flex items-start justify-between">
            <h2 class="text-lg font-semibold text-base-content group-hover:text-primary transition-colors">
              {@name}
            </h2>
            <div class="bg-primary/10 text-primary border border-primary/20 px-2 py-1 text-xs font-mono">
              {if @version, do: "v#{@version}", else: "—"}
            </div>
          </div>

          <p class="flex-1 text-base-content/70 text-sm leading-relaxed min-h-12 line-clamp-2">
            {if @description != "", do: @description, else: "No description available"}
          </p>

          <div class="pt-3 border-t border-base-300">
            <div class="flex items-center space-x-2 text-xs text-base-content/70">
              <.icon name={:download} type={:outline} class="w-3 h-3" />
              <span>{format_count(@download_count)} downloads</span>
            </div>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  defp latest_version(releases) do
    releases
    |> Enum.reject(& &1.yanked_at)
    |> List.last()
    |> then(&(&1 && Map.get(&1, :version)))
  end

  attr :packages, :map, required: true
  attr :featured, :map, default: []

  def packages(assigns) do
    ~H"""
    <div class="py-16 bg-base-200">
      <div class="page-container max-w-7xl">
        <!-- Featured Packages Section -->
        <div class="mb-16">
          <div class="text-center mb-12">
            <div class="flex items-center justify-center space-x-4 mb-6">
              <div class="w-8 h-px bg-primary"></div>
              <h2 class="text-3xl font-bold text-base-content">Featured Packages</h2>
              <div class="w-8 h-px bg-primary"></div>
            </div>
            <p class="text-base-content/70 max-w-2xl mx-auto">
              Discover the most popular and well-maintained packages in our ecosystem
            </p>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for %{name: name, summary: summary, releases: releases} <- @featured do %>
              <.package
                name={name}
                version={latest_version(releases)}
                download_count={Enum.sum(for r <- releases, do: r.download_count)}
                description={summary || ""}
              />
            <% end %>
          </div>
        </div>

        <!-- Most Recent Updates Section -->
        <div class="mb-16">
          <div class="text-center mb-12">
            <div class="flex items-center justify-center space-x-4 mb-6">
              <div class="w-8 h-px bg-secondary"></div>
              <h2 class="text-3xl font-bold text-base-content">Recent Updates</h2>
              <div class="w-8 h-px bg-secondary"></div>
            </div>
            <p class="text-base-content/70 max-w-2xl mx-auto">
              Stay up to date with the latest package releases and improvements
            </p>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for %{name: name, summary: summary, releases: releases} <- Enum.take(@packages, 4) do %>
              <.package
                name={name}
                version={latest_version(releases)}
                download_count={Enum.sum(for r <- releases, do: r.download_count)}
                description={summary || ""}
              />
            <% end %>
          </div>
        </div>

        <!-- Call to Action -->
        <div class="text-center">
          <div class="bg-base-100 border border-base-300 rounded-box py-16 px-8">
            <h3 class="text-2xl font-bold text-base-content mb-4">
              Ready to explore more packages?
            </h3>
            <p class="text-base-content/70 mb-8 max-w-md mx-auto">
              Browse our complete collection of Lua packages and find the perfect tools for your project.
            </p>
            <.link
              navigate={~p"/packages"}
              class="btn btn-primary px-8"
            >
              <.icon name={:folder} type={:outline} class="w-5 h-5 mr-2" /> View All Packages
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
