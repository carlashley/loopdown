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
usage: loopdown [-h] [--advanced-help] [--version] [--log-level [level]] [-n] [-a [app] [[app] ...] | -p [plist] [[plist] ...]] [-m] [-o] [-f] [-i] [-s] [--create-mirror [path]]
                [--cache-server server] [--pkg-server [server]] [--discover-plists]

loopdown can be used to download, install, mirror, or discover information about the additional audio content that Apple provides for the audio editing/mixing software programs
GarageBand, LogicPro X , and MainStage3.

options:
  -h, --help            show this help message and exit
  --advanced-help
  --version             show program's version number and exit
  --log-level [level]   sets the logging level; valid options are: (choices); default is 'info'
  -n, --dry-run         perform a dry run
  -a [app] [[app] ...], --apps [app] [[app] ...]
                        application/s to process package content from; valid options are: 'all', 'garageband', 'logicpro', or 'mainstage', cannot be used with '--discover-plists',
                        requires either '--create-mirror' or '-i/--install'
  -p [plist] [[plist] ...], --plist [plist] [[plist] ...]
                        property list/s to process package content from, use '--discover-plists' to find valid options, cannot be used with '--discover-plists', requires
                        either/both '--cache-server' or '--create-mirror'
  -m, --mandatory       process all mandatory package content, cannot be used with '--discover-plists'
  -o, --optional        process all optional package content, cannot be used with '--discover-plists'
  -f, --force           force install or download regardless of pre-existing installs/download data, cannot be used with '--discover-plists'
  -i, --install         install the audio content packages based on the app/s and mandatory/optional options specified, cannot be used with '--discover-plists', requires
                        either/both '-m/--mandatory' or '-o/--optional', cannot be used with '--create-mirror' or '-p/--plists'
  -s, --silent          suppresses all output on stdout and stderr, cannot be used with '--discover-plists'
  --create-mirror [path]
                        create a local mirror of the 'https://audiocontentdownload.apple.com' directory structure based on the app/s or property list/s being processed, cannot be
                        used with '--discover-plists', requires either/both '-m/--mandatory' or '-o/--optional'
  --cache-server server
                        specify 'auto' for autodiscovery of a caching server or provide a url, for example: 'http://example.org:51000', cannot be used with '--discover-plists',
                        requires either '--create-mirror' or '-i/--install'
  --pkg-server [server]
                        local server of mirrored content, for example 'http://example.org', cannot be used with'--discover-plists', requires '-i/--install'
  --discover-plists     discover the property lists hosted by Apple for GarageBand, Logic Pro X, and MainStage 3

loopdown v1.0.20230726, licensed under the Apache License Version 2.0
```
