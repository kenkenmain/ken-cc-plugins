---
name: minions-set-pipefail
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: plugins/minions/hooks/[^/]*\.sh$
  - field: new_text
    operator: not_contains
    pattern: set -euo pipefail
---

**Hook script missing `set -euo pipefail`!**

Per project code style, every minions hook shell script must include `set -euo pipefail` at the top.

This ensures:
- `-e`: Exit on error
- `-u`: Treat unset variables as errors
- `-o pipefail`: Pipe failures propagate correctly
