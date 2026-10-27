for app <- [:crypto, :public_key, :ssl, :inets], do: Mix.ensure_application!(app)
{:ok, _apps} = Application.ensure_all_started(:phoenix)
ExUnit.start()
