"""Read-only: text/content-desc values from a UI dump XML under the run root."""
import re, sys, pathlib
p = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run') / sys.argv[1]
s = p.read_text(errors='replace')
vals = re.findall(r'(?:text|content-desc)="([^"]+)"', s)
print([v[:60] for v in vals if v.strip()][:60])
