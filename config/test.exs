import Config

# The study tools read the small packs cut by the phone app's
# data/scripts/make_fixtures.py (GenericJam/bezalel) from the real packs.
config :bezalel_core, :packs_dir, Path.expand("../test/fixtures/packs", __DIR__)
