# Job: update-review

<input> is today's Stackbrief report for one Docker host (sections: newer versions, newer
builds of the same tag, HIGH/CRITICAL CVEs with a fix, up-to-date list, notes). The host's
name is in the report's first line.

First read `decisions.md` and `memory/update-review.md` (if it exists).

Sort every actionable item into exactly one of three groups.

**AI** - work an AI coding agent with shell access to the host can do safely, then verify:
- patch/minor version bumps within the same major (e.g. 1.37.4 -> 1.37.5, 2.16.0 -> 2.17.1),
  unless decisions.md says otherwise;
- "newer build of the same version" items (pull + recreate);
- rebuilding locally built images on a fresh base image / updated dependencies to clear their
  CVEs (say which image and that it's a rebuild from source);
- patch layers (images listed in Notes as "patch layer on <official>"): a newer official
  version -> "bump BASE + image tag, rebuild"; a newer official build, or OS-package CVEs with a
  fix showing up again -> "rebuild patch layer (docker pull <BASE>, then build --pull)".
  CVEs in an app's own language packages (Node.js/Python/Go modules) can't be fixed by a patch
  layer -> Waiting, unless the official image has a newer version. Each security line has a
  "packages:" line: "os-pkgs ..." = OS packages (patch layer / rebuild helps), "lang-pkgs ..." =
  the app's own libraries or bundled binaries (only a new upstream release helps).
- Group containers that share an image into one line. Order by risk: internet-facing and
  critical CVEs first (use decisions.md to know which apps are internet-facing), internal last.

**Admin** - things that need a human: major-version or LTS-line migrations, anything
decisions.md routes to Admin, changes needing a GUI, outside accounts, passwords, or a
judgment call (say what the decision is in one line).

**Waiting** - CVEs with no update listed in sections 1 or 2 (maintainers haven't shipped a
fix yet) and pinned images. One line each: app + why nothing can be done now.

Every item in the report must land somewhere or be clearly covered by another line; don't
invent items that aren't in the report.

Output format - your final message must be ONLY this, plain text, no markdown, no preamble:

==== AI ====
<brief instructions: if decisions.md has a "## Brief instructions" section, copy its text here
exactly; otherwise write: On <host from the report>, do these one at a time. For each: snapshot or back up its data, read the release notes, update, test the app, update your docs. Stop and ask me if the release notes mention breaking changes.>
1. <app>: <from> -> <to>  [<why it matters, e.g. "internet-facing, 8 critical CVEs">]
2. ...
Back up, test and validate each change.

==== Admin ====
1. <what to do or decide, one line>

==== Waiting ====
- <app>: <why nothing to do yet>

If a group is empty write "nothing" under it. Keep each line short.

After deciding, update `memory/update-review.md` if you learned something durable.
