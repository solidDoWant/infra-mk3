"""Set yaml.kubernetesCRDStore.url in a VS Code settings file.

Settings files are JSONC (comments, trailing commas), so this edits the text
rather than round-tripping through a JSON parser.
"""

import json
import pathlib
import re
import sys

KEY = "yaml.kubernetesCRDStore.url"

path = pathlib.Path(sys.argv[1])
url = sys.argv[2]
entry = f"{json.dumps(KEY)}: {json.dumps(url)}"

text = path.read_text() if path.exists() else "{\n}\n"
pattern = re.compile(rf'{re.escape(json.dumps(KEY))}\s*:\s*"[^"]*"')

if pattern.search(text):
    text = pattern.sub(lambda _: entry, text, count=1)
else:
    brace = text.index("{")
    rest = text[brace + 1 :]
    # Separate from any existing first entry.
    separator = "," if rest.strip() and not rest.strip().startswith("}") else ""
    text = f"{text[: brace + 1]}\n\t{entry}{separator}{rest}"

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(text)
print(f"Set {KEY} in {path}")
