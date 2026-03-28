## General Info
Test release for the first Swift version; functionality at this stage is generally close to the Python version.

This _should_ build on macOS 14+ and produce a Universal 2 binary in `dist/swift`. This has been built on macOS 14.8.2 using Xcode 15.2.

To build, find the `build.sh` file and run it (it should be in the `loopdown` folder).

## Disclaimer
I'm generally fairly wary of projects that rely on AI to create code, however this project does heavily utilize Claude to convert the concepts in the Python version of this project to Swift. While I've made the best effort I can to not introduce slop or directly copied code, I can't guarantee this hasn't happened. If code is found to be direct copies of code in other projects, please raise an issue with references so I can follow up.

## Support
This is provided 'as is'. Any bugs must be reported as an issue.
No technical support is provided on how to use this in your environment other than what is provided in this read-me or in the help messages in the utility itself.
Issues raised without any debug logging data will be closed without further follow up.

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

## Managed Preferences
This is an experimental implementation of use managed preferences (or even using `defaults` to provide local preferences) for deployment modes.

Preferences can be set with a local `defaults write com.github.carlashley.loopdown` command (or `plistlib` for more complex settings like `appPolicies`) or configuration delivered by MDM or DDM (as long as `com.github.carlashley.loopdown.plist` lands in `/Library/Managed Preferences`).

When using managed preferences to control how `loopdown` runs for deploying content, the following default options are used (but can be overridden):
- deploy mode (not a dry run and output is still sent to console+log)
- cache server auto detected
- install required packages (presumes disk space check passes)

Either a dry-run or deploy run can be called manually from the command line using `loopdown deploy --managed -n` or `loopdown deploy --managed`.


### YAML Preferences
This documents the accepted keys and values for the managed deployment.

It is possible to configure per-app installation of required and/or optional packages using an app policy by using `appPolicies`. This is useful when you might deploy more than one of the audio applications, but only want required content installed for one, but required and optional for another (for example, install required and optional content for GarageBand, but only the required content for Logic Pro).

```
# Preferences for loopdown (domain: 'com.github.carlashley.loopdown').
apps:
  type: [String]
  default: []        # empty = all installed apps
  values: garageband, logicpro, mainstage

required:
  type: Bool
  default: true      # inferred true when both required and optional are absent

optional:
  type: Bool
  default: false

appPolicies:
  type: [{app: String, required: Bool, optional: Bool}]
  default: []        # empty = use top-level required/optional for all apps
  # Per-app overrides for required/optional. Apps not listed fall back to the
  # top-level required/optional values.
  # Example:
  #   - app: garageband
  #     required: true
  #     optional: true
  #   - app: logicpro
  #     required: true
  #     optional: false

forceDeploy:
  type: Bool
  default: false

skipSignatureCheck:
  type: Bool
  default: false

logLevel:
  type: String
  default: info
  values: debug, info, notice, warning, error, critical

cacheServer:
  type: String
  default: auto      # inferred when both cacheServer and mirrorServer are absent
  values: auto, http://host:port

mirrorServer:
  type: String
  default:           # absent; overrides cacheServer when present
  values: https://host

dryRun:
  type: Bool
  default: false     # also overridable by --dry-run CLI flag

quietRun:
  type: Bool
  default: false
```

## License
Licensed under the Apache License Version 2.0. See `LICENSE` for more information.
