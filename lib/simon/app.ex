defmodule Simon.App do
  use Application

  def start(_start_mode, _start_arg) do
    :ok = :syn.add_node_to_scopes([:simon, :behaviour_example])
    Simon.Supervisor.start_link()
  end
end
