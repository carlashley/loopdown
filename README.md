# loopdown
## Requirements
This should run on any version of Python 3 after/including 3.10; `packaging` will need to be installed (a `requirements.txt` file is included in this repo) as `distutils` is deprecated.

## Build
Run `./build.sh` with no additional arguments to create a compressed zipapp version of this utility; please note the default Python interpreter and shebang used is `/usr/bin/env python3`, if a more specific shebang needs to be used, run `./build.sh /new/shebang/path`, for example: `./build.sh /usr/local/bin/python3`. This will generate a new "build" in `./dist/zipapp/usr/local/bin/custom/`.

## Support
This tool is provided 'as is', if an application is prompting to install a package that `loopdown` has installed, please use this [issue form](https://github.com/carlashley/loopdown/issues/new?assignees=carlashley&labels=install+prompt&projects=&template=package-install-prompt-issue.md&title= "raise an issue").
Please note, responses to issues raised may be delayed.

Feature requests can be made, but this project has been deliberately kept to a very defined scope of behaviour/capability.

## License
Licensed under the Apache License Version 2.0. See `LICENSE` for the full license.

## Usage
```
usage: loopdown [-h] [--advanced-help] [-n] [-a [app] [[app] ...] | -p [plist] [[plist] ...]] [-m] [-o] [--cache-server [server]] [--pkg-server [server]] [--create-mirror [path] |
                -i] [--force] [-s] [--log-level [level]] [--version]

options:
  -h, --help            show this help message and exit
  --advanced-help       show hidden arguments; note, not all of these arguments should be directly modified, use these at your own risk
  -n, --dry-run         perform a dry run; no action taken
  -a [app] [[app] ...], --apps [app] [[app] ...]
                        application/s to process package content from; valid values are 'all', 'garageband', 'logicpro', 'mainstage', selecting 'all' will process packages for
                        any/all of the three apps if found on the target device; note that the -p/--plist argument cannot be used with this argument
  -p [plist] [[plist] ...], --plist [plist] [[plist] ...]
                        property list/s to process package content from in the absence of an installed application; note that the -a/--apps argument cannot be used with this
                        argument, use '--discover-plists' to discover available property lists
  -m, --mandatory       select all mandatory packages for processing; this and/or the -o/--optional argument is required
  -o, --optional        select all optional packages for processing; this and/or the -m/--mandatory argument is required
  --cache-server [server]
                        the url representing an Apple caching server instance; for example: 'http://example.org:51492'; note that the --pkg-server argument cannot be used with
                        this argument
  --pkg-server [server]
                        the url representing a local mirror of package content; for example: 'https://example.org/' (the mirror must have the same folder structure as the Apple
                        package server; note that the --cache-server argument cannot be used with this argument
  --create-mirror [path]
                        create a local mirror of the content following the same directory structure as the Apple audio content download structure
  -i, --install         install the content on this device; note, this does not override the Apple package install check scripts, installs will still fail if the Apple install
                        checks fail, for example, an unsupported OS version, or no supported application is installed
  --force               forcibly performs the selected options regardless of pre-existing installations/downloads, etc; this will not force downloads/installs where fetching the
                        audio content fails for various reasons
  -s, --silent          suppresses all output
  --log-level [level]   set the logging level; valid options are 'info', 'debug'
  --version             show program's version number and exit
```
