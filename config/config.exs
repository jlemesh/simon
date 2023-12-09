# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :logger, :console, format: "[$level] $metadata$message\n",
  metadata: [:module, :function, :my_id]
