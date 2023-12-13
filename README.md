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

### How this works
#### Installation/updating on a client Mac - no mirror/caching server
On a Mac with any of the three audio applications installed, `loopdown` inspects the application bundle for a property list file that contains metadata about the audio contents for that version of the application, and based on this information and the options provided to the utility, will either install or update the necessary packages.

#### Installation/updating on a client Mac - mirror/caching server
##### pkg-server
If the `--pkg-server` argument is supplied with a web server as the parameter, `loopdown` will use that URL in place of the Apple CDN. The paths to each package must be an exact mirror of the Apple paths (this can be done by using the `--create-mirror [path]` argument and parameter on a standalone Mac).

For example, if mirroring from `https://example.org`, then the folder paths must match `https://example.org/lp10_ms3_content_2013/[package files]` and/org `https://example.org/lp10_ms3_content_2016/[package files]`.

##### cache-server
If the `--cache-server` argument is supplied with an Apple caching server URL as the parameter, `loopdown` will use that caching server just the same as if the audio application itself was downloading the audio content.

In this particular scenario, if you are _installing_ the audio content packages on multiple clients, best practice is to do this one one Mac first, before proceeding with additional clients.

#### Creating a mirror
A mirror copy of the audio content files can be created on a standalone Mac, it is preferable to have the relevant audio applications installed, but it is not required.

If the applications are installed, the mirror can be created with:
```
> ./loopdown -m -o --create-mirror [path] -a [app]
```

If the applications are not installed, the mirror can be created with:
```
> ./loopdown -m -o --create-mirror [path] -p [plist]
```

#### Discovering content
To find the relevant property lists for use with the `-p/--plist` argument, use the `--discover-plists` argument.


#### Advanced Configuration/Overriding Default Configuration
There are a number of command line arguments that are hidden from the `-h/--help` argument by default, these are used for configuring default parameters, but if necessary these default parameters can be overridden; use the `--advanced-help` argument to show these options.

It is recommended to leave these options as their default settings.


#### Logging
By default, logs are stored in `/Users/Shared/loopdown`. If you need more detailed logging than the standard level, use the `--log-level [level]` argument and parameter.
