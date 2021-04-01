defmodule Trader.Repo.Migrations.AddDataTypeIndex do
  use Ecto.Migration

  def change do
    create index(:data, [:data_type])
  end
end
