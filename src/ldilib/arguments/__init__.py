import tempfile

from pathlib import Path
from .. import _version_string

arg_config = [
    {
        "args": ["--version"],
        "kwargs": {
            "action": "version",
            "dest": "version",
            "version": _version_string,
        },
    },
    {
        "args": ["--log-level"],
        "kwargs": {
            "dest": "log_level",
            "metavar": "[level]",
            "choices": ["info", "debug"],
            "default": "info",
            "required": False,
            "help": "sets the logging level; valid options are: (choices); default is (default)",
        },
    },
    {
        "args": ["-n", "--dry-run"],
        "kwargs": {
            "action": "store_true",
            "dest": "dry_run",
            "required": False,
            "help": "perform a dry run",
        },
    },
    {
        "parser": "apps",
        "args": [
            "-a",
            "--apps",
        ],
        "kwargs": {
            "dest": "apps",
            "nargs": "+",
            "metavar": "[app]",
            "choices": ["all", "garageband", "logicpro", "mainstage"],
            "required": False,
            "help": (
                "application/s to process package content from; valid options are: (choices), "
                "cannot be used with '--discover-plists', requires either '--create-mirror' or '-i/--install'"
            ),
        },
    },
    {
        "parser": "apps",
        "args": [
            "-p",
            "--plist",
        ],
        "kwargs": {
            "dest": "plists",
            "nargs": "+",
            "metavar": "[plist]",
            "required": False,
            "help": (
                "property list/s to process package content from, use '--discover-plists' to find valid options, "
                "cannot be used with '--discover-plists', requires either/both '--cache-server' or '--create-mirror'"
            ),
        },
    },
    {
        "args": ["-m", "--mandatory"],
        "kwargs": {
            "action": "store_true",
            "dest": "mandatory",
            "required": False,
            "help": "process all mandatory package content, cannot be used with '--discover-plists'",
        },
    },
    {
        "args": ["-o", "--optional"],
        "kwargs": {
            "action": "store_true",
            "dest": "optional",
            "required": False,
            "help": "process all optional package content, cannot be used with '--discover-plists'",
        },
    },
    {
        "args": ["-f", "--force"],
        "kwargs": {
            "action": "store_true",
            "dest": "force",
            "required": False,
            "help": (
                "force install or download regardless of pre-existing installs/download data, "
                "cannot be used with '--discover-plists'"
            ),
        },
    },
    {
        "parser": "optn",
        "requires_or": ["mandatory", "optional"],
        "args": [
            "-i",
            "--install",
        ],
        "kwargs": {
            "action": "store_true",
            "dest": "install",
            "required": False,
            "help": (
                "install the audio content packages based on the app/s and mandatory/optional options "
                "specified, cannot be used with '--discover-plists', "
                "requires either/both '-m/--mandatory' or '-o/--optional', cannot be used with '--create-mirror' or "
                "'-p/--plists'"
            ),
        },
    },
    {
        "args": ["-s", "--silent"],
        "kwargs": {
            "action": "store_true",
            "dest": "silent",
            "required": False,
            "help": "suppresses all output on stdout and stderr, cannot be used with '--discover-plists'",
        },
    },
    {
        "parser": "optn",
        "args": ["--create-mirror"],
        "kwargs": {
            "dest": "create_mirror",
            "type": Path,
            "metavar": "[path]",
            "required": False,
            "help": (
                "create a local mirror of the 'https://audiocontentdownload.apple.com' directory structure "
                "based on the app/s or property list/s being processed, cannot be used with '--discover-plists', "
                "requires either/both '-m/--mandatory' or '-o/--optional'"
            ),
        },
    },
    {
        "parser": "down",
        "args": ["--cache-server"],
        "kwargs": {
            "dest": "cache_server",
            "type": str,
            "metavar": "server",
            "required": False,
            "help": (
                "specify 'auto' for autodiscovery of a caching server or provide a url, for example: "
                "'http://example.org:51000', cannot be used with '--discover-plists', requires either "
                "'--create-mirror' or '-i/--install'"
            ),
        },
    },
    {
        "parser": "down",
        "args": ["--pkg-server"],
        "kwargs": {
            "dest": "pkg_server",
            "type": str,
            "metavar": "[server]",
            "required": False,
            "help": (
                "local server of mirrored content, for example 'http://example.org', cannot be used with"
                "'--discover-plists', requires '-i/--install'"
            ),
        },
    },
    {
        "hidden": True,
        "args": ["--default-caching-server-rank"],
        "kwargs": {
            "dest": "default_caching_server_rank",
            "type": int,
            "metavar": "[rank]",
            "default": 1,
            "required": False,
            "help": "specify the default ranking value when looking for caching server; default is (default)",
        },
    },
    {
        "hidden": True,
        "args": ["--default-caching-server-type"],
        "kwargs": {
            "dest": "default_caching_server_type",
            "metavar": "[type]",
            "choices": ["system", "user"],
            "default": "system",
            "required": False,
            "help": (
                "specify the default server type when looking for caching server; valid options are: (choices); "
                "default is (default)"
            ),
        },
    },
    {
        "hidden": True,
        "args": ["--default-log-directory"],
        "kwargs": {
            "dest": "default_log_directory",
            "type": Path,
            "metavar": "[dir]",
            "default": Path("/Users/Shared/loopdown"),
            "required": False,
            "help": "specify the default directory the log is stored in; default is (default)",
        },
    },
    {
        "hidden": True,
        "args": ["--default-packages-download-dest"],
        "kwargs": {
            "dest": "default_packages_download_dest",
            "metavar": "[path]",
            "default": Path("/tmp/loopdown"),
            "required": False,
            "help": "specify the package download path; default is (default)",
        },
    },
    {
        "hidden": True,
        "args": ["--default-working-download-dest"],
        "kwargs": {
            "dest": "default_working_download_dest",
            "type": Path,
            "metavar": "[path]",
            "default": Path(tempfile.gettempdir()).joinpath("loopdown"),
            "required": False,
            "help": (
                "specify the package working download path; default is (default) - note, this may change location "
                "per run"
            ),
        },
    },
    {
        "hidden": True,
        "args": ["--default-warning-threshold"],
        "kwargs": {
            "dest": "default_warn_threshold",
            "type": float,
            "metavar": "[path]",
            "default": 0.5,
            "required": False,
            "help": "specify the default threshold at which a warning about mising downloads and install issues is "
            "displayed; default is (default)",
        },
    },
    {
        "parser": "down",
        "args": ["--discover-plists"],
        "kwargs": {
            "action": "store_true",
            "dest": "discover_plists",
            "required": False,
            "help": "discover the property lists hosted by Apple for GarageBand, Logic Pro X, and MainStage 3",
        },
    },
    {
        "hidden": True,
        "args": ["--discover-plists-range"],
        "kwargs": {
            "dest": "discover_plists_range",
            "type": int,
            "nargs": 2,
            "metavar": ("[min]", "[max]"),
            "default": [0, 99],
            "required": False,
            "help": (
                "specify the start/finish range for property list files; default is (default), "
                "requires '--discover-plists'"
            ),
        },
    },
    {
        "hidden": True,
        "args": ["--feed-base-url"],
        "kwargs": {
            "dest": "feed_base_url",
            "type": str,
            "metavar": "[url]",
            "default": "https://audiocontentdownload.apple.com/lp10_ms3_content_2016/",
            "required": False,
            "help": "specify the default base url for fetching remote property lists; default is (default)",
        },
    },
    {
        "hidden": True,
        "args": ["--max-retries"],
        "kwargs": {
            "dest": "max_retries",
            "type": int,
            "metavar": "[retries]",
            "default": "5",
            "required": False,
            "help": "specify the maximum number of retries for all curl calls; default is (default)",
        },
    },
    {
        "hidden": True,
        "args": ["--max-timeout"],
        "kwargs": {
            "dest": "max_retry_time_limit",
            "type": int,
            "metavar": "[retries]",
            "default": "60",
            "required": False,
            "help": "specify the maximum timeout (in seconds) for all curl calls; default is (default) seconds",
        },
    },
    {
        "hidden": True,
        "args": ["--additional-curl-args"],
        "kwargs": {
            "dest": "proxy_args",
            "nargs": "+",
            "metavar": "[arg]",
            "required": False,
            "help": "provide additional arguments and parameters to all curl calls (use with caution)",
        },
    },
]
