for app <- [:crypto, :public_key, :ssl, :inets], do: Mix.ensure_application!(app)
ExUnit.start()
