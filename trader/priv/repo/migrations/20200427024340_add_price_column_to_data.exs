defmodule Trader.Repo.Migrations.AddPriceColumnToData do
  use Ecto.Migration

  def change do
    alter table(:data) do
      add :id, :bigserial
      add :price, :float
    end

    create index(:data, [:id])
    create index(:data, [:price])
  end
end
