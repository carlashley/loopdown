---
name: Bug report
about: Create a report to help us improve
title: ''
labels: ''
assignees: ''

---

**Describe the bug**
A clear and concise description of what the bug is.

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Exception Errors**
If applicable, please add include the exception errors here; for example:
```
[jappleseed@ungoliant]:loopdown # ./loopdown -n -m -p garageband1047 --create-mirror /tmp/foo
Processing content for: 'garageband1047'
Traceback (most recent call last):
  File "<frozen runpy>", line 198, in _run_module_as_main
  File "<frozen runpy>", line 88, in _run_code
  File "/Users/jappleseed/Documents/github/loopdown/./loopdown/__main__.py", line 118, in <module>
  File "/Users/jappleseed/Documents/github/loopdown/./loopdown/__main__.py", line 66, in main
  File "/Users/jappleseed/Documents/github/loopdown/./loopdown/ldilib/parsers.py", line 68, in parse_packages
  File "/Users/jappleseed/Documents/github/loopdown/./loopdown/ldilib/parsers.py", line 278, in parse_package_for_attrs
  File "/Users/jappleseed/Documents/github/loopdown/./loopdown/ldilib/parsers.py", line 311, in parse_updated_package_attr_vals
KeyError: 'foo'
```

**Debug log**
If possible, please re-run `loopdown` with the `--log-level debug` argument parameter and attached the `/Users/Shared/loopdown/loopdown.log` file once `loopdown` has finished.

**Which macOS Version?**
Output of `sw_vers`:

**Additional context**
Add any other context about the problem here.
