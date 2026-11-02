# Personal Publication Review

Reviewed locally on 2 November 2026. This record covers the independent personal
copy, its retained Git history and the documentation changes made for publication.

## Project origin and ownership

SayFridge began as Team Appix's COMPSCI 734 project. Team members agreed that each
member could maintain a personal copy. This copy is maintained by `syan349`.
The [root README](../../README.md#original-team-contributors) preserves the original
contributors and separates their work from the maintainer's contribution.

## Privacy preparation

- Selected member names and private/school email addresses were replaced in file
  contents, commit messages, and author/committer identities throughout retained history.
- Three original receipt images, one chat screenshot and the original testing
  workbook were removed from history. Redacted images and a sanitized workbook
  were then restored in a new commit.
- The four restored images contain fixed redaction blocks and no image metadata.
  Pixels outside the redaction blocks are unchanged. The workbook keeps all 157
  test records, dates and results, with contributor handles replacing names.
- Public contributor handles remain visible. This is a privacy cleanup, not an
  anonymous project or a transfer of authorship to the personal maintainer.
- Private configuration, cleanup mappings and original-file backups are outside
  the published file set. Only example environment files belong in the repository.
- This local copy has no remote configured. No GitHub repository, team deployment
  or database was changed during this preparation.

The agreed private strings were checked against all reachable Git objects and
current files. Historical image metadata was checked for recorded private strings,
GPS, author/owner fields and camera identifiers. No matching findings remained.
The original team checkout and its recorded Git metadata matched the pre-cleanup
byte baseline after the work.

## Links and environment separation

| Link or setting | Treatment in the personal copy |
| --- | --- |
| Root navigation and screenshots | Point to local guides and image files. The chat screenshot uses the redacted PNG. |
| Original team repository | Retained as a labeled source reference. Its access settings control who can open it. |
| Team Wiki, Issues, PRs, Actions and project boards | Retained in historical guides and reports as course evidence. They are not local setup prerequisites. |
| Original commit identifiers in reports | Preserved as evidence identifiers from the team repository. Rewritten local commits have different hashes. |
| Render/Vercel endpoints in inherited notes and reports | Identify course infrastructure. No availability or credentials check was performed against those services in this review. |
| Personal deployment instructions | Root README and deployment guide use explicit personal API/project settings. Hosting variables must be filled with the operator's own values. |
| Hosted performance harness | `backend/scripts/performance/run_hosted_reads.py` still hardcodes the course endpoint and demo account. Adapt its target and credentials before any personal hosted run; it was not executed in this review. |
| GitHub Releases and CI | No personal release or Actions result exists yet. Historical passing runs describe their recorded team revisions. |

The link review checks local paths and classifies inherited external links. It
does not log into the original private repository or probe live team services.
The Flutter runtime defaults to a local emulator API (or relative `/api/v1` on
Web), and React uses relative `/api/v1`; hosted builds require explicit configuration.

## Licensing and material sources

No project-level `LICENSE` or asset attribution register was found in this copy.
No new open-source license has been assigned during publication preparation.

| Material | Evidence in the repository | Remaining action |
| --- | --- | --- |
| Team-authored code and documentation | Contributor history and the team's agreement to maintain personal copies | Record the team's chosen redistribution/license terms before describing the project as open source. |
| `team-image.jpg` | Illustration of the Fix-It Felix character; no source/license record | Establish the source and permission for redistribution, or remove it from the personal history before public release. It is not used in the personal README. |
| `mobile/assets/` | App illustrations, launcher icon, UI icons and avatars; no creator/source register | Record which files are team-created, generated or third-party, with the applicable source/terms. |
| `web/public/assets/` | Contains copies of Mobile artwork | Apply the same provenance decisions to both copies. |
| `mobile/assets/icons/social/` | Google, Apple, Facebook and Twitter logos | Record the source and applicable brand-asset terms separately from team artwork. |
| `docs/images/readme/` | Application screenshots and widget renders | Preserve test context; resolve the provenance of artwork appearing within the UI. |
| `backend/tests/receipts/` | Redacted photographs used as recognition fixtures | Confirm permission to redistribute the photographs; keep their redactions. |
| Third-party packages | Python requirements, npm lockfile and Flutter lockfile | Retain dependency notices when distributing builds; package licenses do not license the team's own work. |

The pending source and license decisions above remain separate from the completed
personal-data cleanup. Public release should follow those decisions.

## Local verification

| Check | Result |
| --- | --- |
| Markdown links | Local file targets and section anchors were checked across the repository, including archived Markdown; no missing targets or unmatched anchors were found. |
| Image privacy, demo email validation and security selection | 21 tests passed on 2 November 2026. |
| Restored receipt fixtures | All three PNGs pass the application image-type and batch-size validators. |
| Restored workbook | All 1,642 populated cells match the original values after the specified identity substitutions; 157 records retained. |
| Full database-free Backend collection | Stopped when the tokenizer tried to download a missing dictionary without network access. No full-suite pass is claimed. |
| Live model, hosted services and database | Not exercised during this local publication preparation. |

Before a personal release, rerun the project checks for the selected personal
commit and record the result separately from the retained course evidence.
