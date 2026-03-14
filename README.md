## General Info
Test release for the first Swift version; functionality at this stage is generally close to the Python version.

This _should_ build on macOS 14+ and produce a Universal 2 binary in `dist/swift`. This has been built on macOS 14.8.2 using Xcode 15.2.

To build, find the `build.sh` file and run it (it should be in the `loopdown` folder).

## Known/Possible Issues
- Deployment with cache server or mirror server has not yet been tested


## Build options are:
```
./build.sh              # universal (default)
./build.sh universal    # same
./build.sh arm64        # Apple Silicon only
./build.sh x86_64       # Intel only
```
## Output:
```
../dist/swift/universal/loopdown   # ./build.sh or ./build.sh universal
../dist/swift/arm64/loopdown       # ./build.sh arm64
../dist/swift/x86_64/loopdown      # ./build.sh x86_64
```

## Example Usage:
```
[foo@bar]:loopdown/dist/swift/universal # ./loopdown -h 
OVERVIEW: Manage additional content for Apple's audio applications, GarageBand, Logic Pro, and/or MainStage.

These arguments are supported in both 'deploy' and 'download' commands:
  -n, --dry-run     Perform a dry run.
  -a, --app <app>   Install content for an app (default: all supported apps).
  -r, --required    Select required content.
  -o, --optional    Select optional content.

COMMENTS:
  -r, --required / -o, --optional one or both are required.
  -a, --app is not required; omitting this will trigger content processing for all applicable apps installed.

USAGE: loopdown <subcommand>

OPTIONS:
  --version               Show the version.
  -h, --help              Show help information.

SUBCOMMANDS:
  deploy                  Install content for selected apps; requires root level privilege.
  download                Download content for selected apps.

  See 'loopdown help <subcommand>' for detailed help.
```

## License
Licensed under the Apache License Version 2.0. See `LICENSE` for more information.
