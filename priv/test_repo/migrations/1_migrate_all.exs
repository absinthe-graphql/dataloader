defmodule Absinthe.Ecto.TestRepo.Migrations.MigrateAll do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :username, :string
    end

    create table(:posts) do
      add :user_id, references(:users)
    end
  end
end
