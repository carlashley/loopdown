import logging
import subprocess

log = logging.getLogger(__name__)


def installer(pkg: str, *, target: str = "/") -> bool:
    """Subprocess the '/usr/sbin/installer' binary. If the install is successful then the success result
    message is returned. Failures are logged.
    The 'target' param passed on to 'installer' is set to '/'; while 'installer' supports other values, this
    is deliberately set to '/'; no other value will be supported by this wrapper function.
    :param pkg: package path as string
    :param target: the target argument that the installer binary requires; default is '/'"""
    cmd = ["/usr/sbin/installer", "-pkg", pkg, "-target", target]

    try:
        p = subprocess.run(cmd, capture_output=True, encoding="utf-8", check=True)
    except subprocess.CalledProcessError as e:
        log.debug(f"{' '.join(cmd)} exited with returncode {e.returncode}; stdout: {e.stdout}, stderr: {e.stderr}")
        return False

    lines = (p.stdout or "").splitlines()
    last = lines[-1] if lines else ""
    output = last.split(": ")[-1].strip() if last else ""

    return " success" in output
