defmodule Absinthe.Ecto.TestRepo.Migrations.MigrateAll do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :username, :string
    end

    create table(:posts) do
      add :user_id, references(:users)
      add :title, :string
      add :deleted_at, :utc_datetime
    end

    create table(:likes) do
      add :user_id, references(:users), null: false
      add :post_id, references(:posts), null: false
    end
  end
end
