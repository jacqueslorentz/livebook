defmodule LivebookWeb.SessionLive.AppDockerComponent do
  use LivebookWeb, :live_component

  import Ecto.Changeset

  alias Livebook.Hubs
  alias Livebook.FileSystem
  alias LivebookWeb.AppComponents
  alias Livebook.Hubs.Provider

  @impl true
  def update(assigns, socket) do
    deployment_group_changed? =
      not Map.has_key?(socket.assigns, :deployment_group_id) or
        socket.assigns.deployment_group_id != assigns.deployment_group_id

    socket = assign(socket, assigns)
    deployment_groups = Provider.deployment_groups(assigns.hub)

    socket =
      socket
      |> assign(settings_valid?: Livebook.Notebook.AppSettings.valid?(socket.assigns.settings))
      |> assign(
        hub_secrets: Hubs.get_secrets(assigns.hub),
        hub_file_systems: Hubs.get_file_systems(assigns.hub, hub_only: true),
        deployment_groups: deployment_groups,
        deployment_group_form: %{"deployment_group_id" => assigns.deployment_group_id},
        deployment_group_id: assigns.deployment_group_id
      )
      |> assign_new(:save_result, fn -> nil end)

    socket =
      if deployment_group_changed? do
        assign(socket, :changeset, Hubs.Dockerfile.config_changeset(base_config(socket)))
      else
        socket
      end

    {:ok, update_dockerfile(socket)}
  end

  defp base_config(socket) do
    if id = socket.assigns.deployment_group_id do
      deployment_group = Enum.find(socket.assigns.deployment_groups, &(&1.id == id))

      %{
        Hubs.Dockerfile.config_new()
        | clustering: deployment_group.clustering,
          zta_provider: deployment_group.zta_provider,
          zta_key: deployment_group.zta_key
      }
    else
      Hubs.Dockerfile.config_new()
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 flex flex-col space-y-8">
      <h3 class="text-2xl font-semibold text-gray-800">
        App deployment with Docker
      </h3>
      <.content
        file={@file}
        settings_valid?={@settings_valid?}
        hub={@hub}
        deployment_groups={@deployment_groups}
        deployment_group_form={@deployment_group_form}
        deployment_group_id={@deployment_group_id}
        changeset={@changeset}
        session={@session}
        dockerfile={@dockerfile}
        warnings={@warnings}
        save_result={@save_result}
        myself={@myself}
      />
    </div>
    """
  end

  defp content(%{file: nil} = assigns) do
    ~H"""
    <div class="flex justify-between">
      <p class="text-gray-700">
        To deploy this app, make sure to save the notebook first.
      </p>
      <.link
        class="text-blue-600 font-medium"
        patch={~p"/sessions/#{@session.id}/settings/file?context=app-docker"}
      >
        <span>Save</span>
        <.remix_icon icon="arrow-right-line" />
      </.link>
    </div>
    """
  end

  defp content(%{settings_valid?: false} = assigns) do
    ~H"""
    <div class="flex justify-between">
      <p class="text-gray-700">
        To deploy this app, make sure to specify valid settings.
      </p>
      <.link
        class="text-blue-600 font-medium"
        patch={~p"/sessions/#{@session.id}/settings/app?context=app-docker"}
      >
        <span>Configure</span>
        <.remix_icon icon="arrow-right-line" />
      </.link>
    </div>
    """
  end

  defp content(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <p class="text-gray-700">
        You can deploy this app in the cloud using Docker. To do that, configure
        the deployment and then use the generated Dockerfile.
      </p>
      <div class="flex gap-12">
        <p class="text-gray-700">
          <.label>Hub</.label>
          <span>
            <span class="text-lg"><%= @hub.hub_emoji %></span>
            <span><%= @hub.hub_name %></span>
          </span>
        </p>
        <%= if @deployment_groups do %>
          <%= if @deployment_groups != [] do %>
            <.form
              for={@deployment_group_form}
              phx-change="select_deployment_group"
              phx-target={@myself}
              id="select_deployment_group_form"
            >
              <.select_field
                help={deployment_group_help()}
                field={@deployment_group_form[:deployment_group_id]}
                options={deployment_group_options(@deployment_groups)}
                label="Deployment Group"
                name="deployment_group_id"
                value={@deployment_group_id}
              />
            </.form>
          <% else %>
            <p class="text-gray-700">
              <.label help={deployment_group_help()}>
                Deployment Group
              </.label>
              <span>No deployment groups available</span>
            </p>
          <% end %>
        <% end %>
      </div>
      <div :if={@warnings != []} class="flex flex-col gap-2">
        <.message_box :for={warning <- @warnings} kind={:warning}>
          <%= raw(warning) %>
        </.message_box>
      </div>
      <.form :let={f} for={@changeset} as={:data} phx-change="validate" phx-target={@myself}>
        <div class="flex flex-col space-y-4">
          <AppComponents.deployment_group_form_content
            hub={@hub}
            form={f}
            disabled={@deployment_group_id != nil}
          />
          <AppComponents.docker_config_form_content hub={@hub} form={f} />
        </div>
      </.form>
      <.save_result :if={@save_result} save_result={@save_result} />
      <AppComponents.docker_instructions
        hub={@hub}
        dockerfile={@dockerfile}
        dockerfile_config={apply_changes(@changeset)}
      >
        <:dockerfile_actions>
          <.button
            color="gray"
            small
            type="button"
            aria-label="save dockerfile alongside the notebook"
            phx-click="save_dockerfile"
            phx-target={@myself}
          >
            <.remix_icon icon="save-line" />
            <span>Save alongside notebook</span>
          </.button>
        </:dockerfile_actions>
      </AppComponents.docker_instructions>
    </div>
    """
  end

  defp save_result(%{save_result: {:ok, file}}) do
    assigns = %{path: file.path}

    ~H"""
    <.message_box kind={:info} message={"File saved at #{@path}"} />
    """
  end

  defp save_result(%{save_result: {:error, message}}) do
    assigns = %{message: message}

    ~H"""
    <.message_box kind={:error} message={@message} />
    """
  end

  @impl true
  def handle_event("validate", %{"data" => data}, socket) do
    changeset =
      socket
      |> base_config()
      |> Hubs.Dockerfile.config_changeset(data)
      |> Map.replace!(:action, :validate)

    {:noreply, assign(socket, changeset: changeset) |> update_dockerfile()}
  end

  def handle_event("save_dockerfile", %{}, socket) do
    dockerfile_file = FileSystem.File.resolve(socket.assigns.file, "./Dockerfile")

    save_result =
      case FileSystem.File.write(dockerfile_file, socket.assigns.dockerfile) do
        :ok -> {:ok, dockerfile_file}
        {:error, message} -> {:error, message}
      end

    {:noreply, assign(socket, save_result: save_result)}
  end

  def handle_event("select_deployment_group", %{"deployment_group_id" => id}, socket) do
    id = if(id != "", do: id)
    Livebook.Session.set_notebook_deployment_group(socket.assigns.session.pid, id)

    {:noreply, socket}
  end

  defp update_dockerfile(socket) when socket.assigns.file == nil do
    assign(socket, dockerfile: nil, warnings: [])
  end

  defp update_dockerfile(socket) do
    config = apply_changes(socket.assigns.changeset)

    %{
      hub: hub,
      hub_secrets: hub_secrets,
      hub_file_systems: hub_file_systems,
      file: file,
      file_entries: file_entries,
      secrets: secrets,
      app_settings: app_settings,
      deployment_groups: deployment_groups,
      deployment_group_id: deployment_group_id
    } = socket.assigns

    deployment_group =
      if deployment_group_id, do: Enum.find(deployment_groups, &(&1.id == deployment_group_id))

    hub_secrets =
      if deployment_group do
        Enum.uniq_by(deployment_group.secrets ++ hub_secrets, & &1.name)
      else
        hub_secrets
      end

    dockerfile =
      Hubs.Dockerfile.build_dockerfile(
        config,
        hub,
        hub_secrets,
        hub_file_systems,
        file,
        file_entries,
        secrets
      )

    warnings =
      Hubs.Dockerfile.warnings(
        config,
        hub,
        hub_secrets,
        hub_file_systems,
        app_settings,
        file_entries,
        secrets
      )

    assign(socket, dockerfile: dockerfile, warnings: warnings)
  end

  defp deployment_group_options(deployment_groups) do
    for deployment_group <- [%{name: "none", id: nil}] ++ deployment_groups,
        do: {deployment_group.name, deployment_group.id}
  end

  defp deployment_group_help() do
    "Share deployment credentials, secrets, and configuration with deployment groups."
  end
end
