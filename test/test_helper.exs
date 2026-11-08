# `:ssl` comes from the app's own `extra_applications`, so the TLS tests
# fail if it is ever dropped; `:inets` is only the tests' HTTP client.
Mix.ensure_application!(:inets)
{:ok, _apps} = Application.ensure_all_started(:phoenix)
ExUnit.start()
