defmodule CalexWeb.PageController do
  use CalexWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
