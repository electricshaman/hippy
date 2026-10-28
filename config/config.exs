import Config

if config_env() == :test do
  config :hippy, req_options: [plug: {Req.Test, Hippy.Server}]
end
