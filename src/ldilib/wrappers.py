"""Python wrappers of various system binaries or other Python packages."""
import subprocess


def curl(*args, **kwargs) -> subprocess.CompletedProcess:
    """Wraps '/usr/bin/curl'.
    This wrapper defaults to following redirects (max follow depth of 5 redirects), and includes
    the user agent string in all operations.
    :param *args: arguments to pass to the system binary
    :param **kwargs: arguments to pass to the subprocess call"""
    cmd = ["/usr/bin/curl", "-L", "--max-redirs", "5", "--user-agent", "loopdown/1", *args]
    return subprocess.run(cmd, **kwargs)


def diskutil(*args, **kwargs) -> subprocess.CompletedProcess:
    """Wraps '/usr/sbin/diskutil'.
    :param *args: arguments to pass to the system binary
    :param **kwargs: arguments to pass to the subprocess call"""
    cmd = ["/usr/sbin/diskutil", *args]
    return subprocess.run(cmd, **kwargs)


def installer(*args, **kwargs) -> subprocess.CompletedProcess:
    """Wraps '/usr/sbin/installer'.
    :param *args: arguments to pass to the system binary
    :param **kwargs: arguments to pass to the subprocess call"""
    cmd = ["/usr/sbin/installer", *args]
    return subprocess.run(cmd, **kwargs)


def pkgutil(*args, **kwargs) -> subprocess.CompletedProcess:
    """Wraps '/usr/sbin/pkgutil'.
    :param *args: arguments to pass to the system binary
    :param **kwargs: arguments to pass to the subprocess call"""
    cmd = ["/usr/sbin/pkgutil", *args]
    return subprocess.run(cmd, **kwargs)


def sw_vers(*args, **kwargs) -> subprocess.CompletedProcess:
    """Wraps '/usr/bin/sw_vers'.
    :param *args: arguments to pass to the system binary
    :param **kwargs: arguments to pass to the subprocess call"""
    cmd = ["/usr/bin/sw_vers", *args]
    return subprocess.run(cmd, **kwargs)
