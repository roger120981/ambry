defmodule AmbryWeb.Admin.MediaLive.Index do
  @moduledoc """
  LiveView for media admin interface.
  """

  use AmbryWeb, :admin_live_view

  import AmbryWeb.Admin.PaginationHelpers
  import AmbryWeb.TimeUtils

  alias Ambry.Media
  alias Ambry.PubSub

  @valid_sort_fields [
    :status,
    :book,
    :series,
    :authors,
    :narrators,
    :duration,
    :published,
    :inserted_at
  ]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    if connected?(socket) do
      :ok = PubSub.subscribe("media:*")
    end

    {:ok,
     socket
     |> assign(page_title: "Media", default_sort: "inserted_at.desc")
     |> set_in_progress_media()
     |> maybe_update_media(params, true)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _url, socket) do
    {:noreply, maybe_update_media(socket, params)}
  end

  defp maybe_update_media(socket, params, force \\ false) do
    old_list_opts = get_list_opts(socket)
    new_list_opts = get_list_opts(params)
    list_opts = Map.merge(old_list_opts, new_list_opts)

    if list_opts != old_list_opts || force do
      {media, has_more?} = list_media(list_opts, socket.assigns.default_sort)

      socket
      |> assign(:list_opts, list_opts)
      |> assign(:has_more?, has_more?)
      |> assign(:media, media)
    else
      socket
    end
  end

  defp refresh_media(socket) do
    list_opts = get_list_opts(socket)

    params = %{
      "filter" => to_string(list_opts.filter),
      "page" => to_string(list_opts.page)
    }

    socket
    |> maybe_update_media(params, true)
    |> set_in_progress_media()
  end

  defp set_in_progress_media(socket) do
    if connected?(socket) do
      known_processing_media = Map.get(socket.assigns, :processing_media, [])
      progress_map = Map.get(socket.assigns, :processing_media_progress_map, %{})

      {current_processing_media, _has_more?} = Media.list_media(0, 999, %{status: :processing}, desc: :inserted_at)

      to_add = Enum.map(current_processing_media -- known_processing_media, & &1.id)
      to_remove = Enum.map(known_processing_media -- current_processing_media, & &1.id)

      progress_map = Map.drop(progress_map, to_remove)

      Enum.each(to_add, &(:ok = PubSub.subscribe("media-progress:#{&1}")))
      Enum.each(to_remove, &(:ok = PubSub.unsubscribe("media-progress:#{&1}")))

      assign(socket, %{
        processing_media: current_processing_media,
        processing_media_progress_map: progress_map
      })
    else
      assign(socket,
        processing_media: [],
        processing_media_progress_map: %{}
      )
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    media = Media.get_media!(id)
    :ok = Media.delete_media(media)

    {:noreply, refresh_media(socket)}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    socket = maybe_update_media(socket, %{"filter" => query, "page" => "1"})
    list_opts = get_list_opts(socket)

    {:noreply, push_patch(socket, to: ~p"/admin/media?#{patch_opts(list_opts)}")}
  end

  def handle_event("row-click", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/media/#{id}/edit")}
  end

  def handle_event("sort", %{"field" => sort_field}, socket) do
    list_opts =
      socket
      |> get_list_opts()
      |> Map.update!(:sort, &apply_sort(&1, sort_field, @valid_sort_fields))

    {:noreply, push_patch(socket, to: ~p"/admin/media?#{patch_opts(list_opts)}")}
  end

  defp list_media(opts, default_sort) do
    filters = if opts.filter, do: %{search: opts.filter}, else: %{}

    Media.list_media(
      page_to_offset(opts.page),
      limit(),
      filters,
      sort_to_order(opts.sort || default_sort, @valid_sort_fields)
    )
  end

  @impl Phoenix.LiveView

  def handle_info(%PubSub.Message{type: :media, action: :progress} = message, socket) do
    %{id: media_id, meta: %{progress: progress}} = message

    progress_map =
      socket.assigns
      |> Map.get(:processing_media_progress_map, %{})
      |> Map.put(media_id, progress)

    {:noreply, assign(socket, :processing_media_progress_map, progress_map)}
  end

  def handle_info(%PubSub.Message{type: :media}, socket), do: {:noreply, refresh_media(socket)}

  defp format_published(%{published: nil}), do: nil
  defp format_published(%{published_format: :full, published: date}), do: Calendar.strftime(date, "%x")
  defp format_published(%{published_format: :year_month, published: date}), do: Calendar.strftime(date, "%Y-%m")
  defp format_published(%{published_format: :year, published: date}), do: Calendar.strftime(date, "%Y")

  defp status_color(:pending), do: :yellow
  defp status_color(:processing), do: :blue
  defp status_color(:error), do: :red
  defp status_color(:ready), do: :brand

  defp progress_percent(nil), do: "0.0"

  defp progress_percent(%Decimal{} = progress) do
    progress
    |> Decimal.mult(100)
    |> Decimal.round(1)
    |> Decimal.to_string()
  end
end
