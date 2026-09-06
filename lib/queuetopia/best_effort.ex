defmodule Queuetopia.BestEffort do
  @moduledoc false

  require Logger

  def run(label, fun) do
    fun.()
  rescue
    exception ->
      Logger.error(label <> " failed: " <> Exception.format(:error, exception, __STACKTRACE__))

      nil
  end
end
