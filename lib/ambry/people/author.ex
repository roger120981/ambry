defmodule Ambry.People.Author do
  @moduledoc """
  An author writes books.

  Belongs to a Person, so one person can write as multiple authors (pen names).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ambry.People.BookAuthor
  alias Ambry.People.Person

  schema "authors" do
    has_many :book_authors, BookAuthor
    has_many :books, through: [:book_authors, :book]
    belongs_to :person, Person

    field :name, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(author, attrs) do
    author
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> foreign_key_constraint(:id,
      name: "authors_books_author_id_fkey",
      message:
        "This author is in use by one or more books. You must first remove them as an author from any associated books."
    )
  end
end
