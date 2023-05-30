"""CURL request handling"""
from pathlib import Path
from typing import Optional
from .wrappers import curl


class RequestMixin:
    def get_headers(self, url: str, _sep: str = ": ") -> dict[str, str | int]:
        """Get the headers for a given URL, returned as a dictionary object."""
        result = {}
        redir_str = "\r\n\r"  # url redirects output includes this line break pattern
        http_prefixes = ["HTTP/1", "HTTP/2", "HTTP/3"]
        args = ["--silent", "-I", url]
        kwargs = {"capture_output": True, "encoding": "utf-8"}
        p = curl(*args, **kwargs)

        if p.returncode == 0:
            # Handle redirect codes 301, 302 Found/Moved Temp, 303, 307, and/or 308
            if redir_str in p.stdout.strip():
                stdout = p.stdout.strip().split(redir_str)[-1]  # last "line" is the header to parse
            else:
                stdout = p.stdout.strip()

            # Now construct dictionary of header values
            for line in stdout.splitlines():
                line = line.strip()

                # HTTP status line doesn't have the ":" header separator in it
                if any(line.startswith(prfx) for prfx in http_prefixes):
                    result["status"] = int(line.split(" ")[1])
                else:
                    key_val = line.split(_sep)
                    key, val = key_val[0].lower(), "".join(key_val[1:])
                    val = None if val == "" else val

                    if val and all(char.isdigit() for char in val):
                        val = int(val)

                    if not key == "":
                        result[key] = val
        else:
            self.log.error(f"'curl {' '.join(args)}' exited with returncode {p.returncode}: {p.stderr.strip()}")
        return result

    def is_compressed(self, url: str, _header: str = "content-encoding", _encoding: str = "gzip") -> bool:
        """Determine if the URL has a 'Content-Encoding' header and a value that represents a compressed file type.
        :param url: url to check the content-encoding header value of"""
        return self.get_headers(url).get(_header, False) == _encoding

    def is_status_ok(self, url: str, _ok_statuses: list[int] = [*range(200, 300)]) -> bool:
        """Determine if the URL has a status code that is in an OK range.
        :param url: url to check the status code of"""
        args = ["-I", "--silent", "-o", "/dev/null", "-w", "%{http_code}", url]
        kwargs = {"capture_output": True, "encoding": "utf-8"}
        p = curl(*args, **kwargs)

        if p.returncode == 0:
            status = int(p.stdout.strip())
            self.log.warning(f"{url} - HTTP {status}")
            return status in _ok_statuses
        else:
            self.log.error(f"'curl {' '.join(args)}' exited with returncode {p.returncode}: {p.stderr.strip()}")
            return False

    def get_file(self, url: str, dest: Path, silent: bool = False) -> Optional[Path]:
        """Get a file from the provided URL. This method checks if the requested file is compressed, automatically
        using the curl parameter '--compressed' if the 'content-encoding' header exists and has a 'gzip' value (this
        is the compression type used by Apple for these downloads).
        :param url: url to retrieve
        :param dest: destination the file will be saved to
        :param silent: perform file retrieval silently; default False"""
        args = ["--silent" if silent else "--progress-bar", url, "-o", str(dest), "--create-dirs"]
        kwargs = {"capture_output": silent}

        if self.cache_server and "&source" in url:
            args.extend("--noproxy", "*")

        if self.is_compressed(url):
            args.extend(["--compressed"])

        p = curl(*args, **kwargs)

        if p.returncode == 0:
            if dest.exists() and dest.stat().st_size > 0:
                return dest
        else:
            self.log.error(f"'curl {' '.join(args)}' exited with returncode {p.returncode}: {p.stderr.strip()}")
