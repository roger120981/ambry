defmodule Ambry.People.Person do
  @moduledoc """
  A person with a bio.

  Can be (multiple) authors and narrators. (Not used for users).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.Paths
  alias Ambry.People.Author
  alias Ambry.People.Narrator
  alias Ambry.Thumbnails

  schema "people" do
    has_many :authors, Author, on_replace: :delete
    has_many :narrators, Narrator, on_replace: :delete

    embeds_one :thumbnails, Thumbnails, on_replace: :delete

    field :name, :string
    field :description, :string
    field :image_path, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(person, attrs) do
    person
    |> cast(attrs, [:name, :description, :image_path])
    |> cast_assoc(:authors,
      sort_param: :authors_sort,
      drop_param: :authors_drop
    )
    |> cast_assoc(:narrators,
      sort_param: :narrators_sort,
      drop_param: :narrators_drop
    )
    |> cast_embed(:thumbnails)
    |> maybe_clear_thumbnails()
    |> validate_required([:name])
    |> validate_image_path()
    |> foreign_key_constraint(:author, name: "authors_books_author_id_fkey")
    |> foreign_key_constraint(:narrator, name: "media_narrators_narrator_id_fkey")
    |> check_constraint(:thumbnails, name: "thumbnails_original_match_constraint")
  end

  # if the image_path changes, clear the thumbnails embed
  defp maybe_clear_thumbnails(changeset) do
    case fetch_change(changeset, :image_path) do
      {:ok, _new_path} -> put_embed(changeset, :thumbnails, nil)
      _ -> changeset
    end
  end

  defp validate_image_path(changeset) do
    validate_change(changeset, :image_path, fn :image_path, path ->
      case path do
        "/uploads/" <> _ = path ->
          if path |> Paths.web_to_disk() |> File.exists?() do
            []
          else
            [image_path: "file does not exist"]
          end

        nil ->
          []

        _ ->
          [image_path: "must begin with /uploads/"]
      end
    end)
  end
end
