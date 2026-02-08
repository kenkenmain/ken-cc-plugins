---
name: minions-hook-validation
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: plugins/minions/hooks/.*\.sh$
---

**Hook script modified — remember to run `bash -n` validation!**

You're editing a minions hook shell script. Per project code style:
- Always run `bash -n <script>` after modifying hook shell scripts
- This catches syntax errors before they break the workflow at runtime

**Required action:** Run `bash -n` on the modified script before committing.
