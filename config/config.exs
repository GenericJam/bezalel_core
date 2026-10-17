import Config

# Where the study packs are (Bezalel.Study.DB.dir/0) is the host app's to
# say: a path, or {module, function, args} returning one. Bezalel's phone app
# points it at its app-support directory; tests at test/fixtures/packs.

import_config "#{config_env()}.exs"
