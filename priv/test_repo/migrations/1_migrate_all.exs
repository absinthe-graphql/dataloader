defmodule Absinthe.Ecto.TestRepo.Migrations.MigrateAll do
  use Ecto.Migration

  def change do
    create table(:leaderboards) do
      add :name, :string
    end

    create table(:users) do
      add :username, :string
      add :leaderboard_id, references(:leaderboards)
    end

    create table(:posts) do
      add :user_id, references(:users)
      add :title, :string
      add :status, :string
      add :deleted_at, :utc_datetime
    end

    create table(:likes) do
      add :user_id, references(:users), null: false
      add :post_id, references(:posts), null: false
    end

    create table(:scores) do
      add :leaderboard_id, references(:leaderboards), null: false
      add :post_id, references(:posts), null: false
    end

    create table(:pictures) do
      add :status, :string
      add :url, :string, null: false
    end

    create table(:user_pictures) do
      add :status, :string
      add :user_id, references(:users), null: false
      add :picture_id, references(:pictures), null: false
    end
  end
end
