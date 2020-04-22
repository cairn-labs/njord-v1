defmodule Trader.Repo.Migrations.AddDataSelector do
  use Ecto.Migration

  def change do
    alter table(:data) do
      add :selector, :text
    end

    create index(:data, [:selector])
  end
end
