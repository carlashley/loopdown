---
name: Package Install Prompt Issue
about: Application prompting to install package already installed by loopdown
title: ''
labels: install prompt
assignees: carlashley

---

Please use this to raise an issue when a package is installed by `loopdown` but the target application continues to prompt to install it.

**Which `loopdown` version?**
Output of `loopdown --version`:

**What applications are you installing packages for (delete those that don't apply)?**
- :white_check_mark: GarageBand (version: )
- :white_check_mark: Logic Pro (version: )
- :white_check_mark: MainStage 3 (version: )

**Are the packages being installed for the first time, or an upgrade?**
- :white_check_mark: First Time
- :white_check_mark: Upgrade

**Which packages are installed but still prompt to be installed?**
Please include the folder path and package name including the file extension; for example:
- `lp10_ms3_content_2016/MAContent10_AssetPack_0668_AppleLoopsReggaetonPop.pkg`

**Is the `--pkg-server` argument being used?**
- :white_check_mark: Yes
- :white_check_mark: No

**If the `--pkg-server` argument has been used, have the packages been refreshed within the last week?**
- :white_check_mark: Yes
- :white_check_mark: No

**Is the `--cache-server` argument being used?**
- :white_check_mark: Yes
- :white_check_mark: No

**If the `--cache-server` has been used, has `loopdown` been run on one Mac to pre-warm the cache?**
- :white_check_mark: Yes
- :white_check_mark: No


Has the `--log-level debug` argument and parameter been used?
If `loopdown` has been run with `--log-level debug`, please attach the output of the log run.
Log files are stored in `/Users/Shared/loopdown`; the most recent log will be `/Users/Shared/loopdown/loopdown.log`
- :white_check_mark: Yes
- :white_check_mark: No



**Which macOS Version?**
Output of `sw_vers`:
