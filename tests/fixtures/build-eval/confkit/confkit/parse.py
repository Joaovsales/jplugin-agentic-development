"""Parse one INI document into sections of key/value strings."""


class ParseError(ValueError):
    """The text is not valid INI; carries the 1-based line number."""

    def __init__(self, line_no: int, message: str) -> None:
        super().__init__(f"line {line_no}: {message}")
        self.line_no = line_no
        self.message = message


def parse_ini(text: str) -> dict[str, dict[str, str]]:
    """Return {section: {key: value}}, keeping the case of names as written.

    Blank lines and lines starting with '#' or ';' are skipped. A later duplicate key
    in a section replaces the earlier one. Raises ParseError on the first bad line.
    """
    sections: dict[str, dict[str, str]] = {}
    current: dict[str, str] | None = None
    for line_no, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line[0] in "#;":
            continue
        if line.startswith("[") and line.endswith("]"):
            current = sections.setdefault(line[1:-1].strip(), {})
            continue
        if current is None:
            raise ParseError(line_no, "key outside any section")
        if "=" not in line:
            raise ParseError(line_no, "expected key = value")
        key, _, value = line.partition("=")
        current[key.strip()] = value.strip()
    return sections
