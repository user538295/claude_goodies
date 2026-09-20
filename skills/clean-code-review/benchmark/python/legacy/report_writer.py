"""FileReportWriter — INFRASTRUCTURE adapter. Flat-sprawl fixture for arch-17."""


class FileReportWriter:
    """Writes a report to the local filesystem — concrete infrastructure I/O."""

    def __init__(self, directory: str) -> None:
        self._directory = directory

    def write(self, name: str, contents: str) -> None:
        with open(f"{self._directory}/{name}", "w", encoding="utf-8") as handle:
            handle.write(contents)
