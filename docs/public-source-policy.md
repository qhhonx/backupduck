# Public-source contribution policy

English is the primary language for project documentation, design contracts,
contribution instructions, release notes and code comments. Product localization
and clearly labeled translated user guides may use other languages. The product
name may retain its localized spelling.

## Publishable material

Include implementation source, required assets, reproducible build/test scripts,
license information and contributor-facing design or architecture contracts.
Documentation must describe behavior, rationale, reproduction steps and limits
without depending on a private conversation or development machine.

Translate and edit useful contracts rather than publishing development diaries.
A translation alone does not make a personal acceptance log appropriate for a
source release. Design references use synthetic data and disclose their scope.
Unfinished platforms must be identified as unfinished.

## Local-only material

Do not commit personal acceptance discussions, chat attachments, installation
receipts, device/account details, machine paths, agent handoffs, private task or
preview links, temporary captures, generated logs or signing material.

Use ignored local storage for working evidence, such as `build/internal-docs/`.
Retain needed local records before removing them from the release tree. Ignore
rules do not remove files that are already tracked. Review tracked files and
links as well as new files before preparing a commit.

## Checks

Run the existing credential/path scan and the documentation checks before a
source release:

```sh
python3 scripts/audit-public.py --documentation
```

To inspect the actual Git index rather than the working files:

```sh
python3 scripts/audit-public.py --staged --documentation
```

The index check includes the entire candidate tree, not only changed files.
It detects common private material, internal design-record names and substantial
Chinese prose in primary Markdown documentation. Explicit `.zh-CN.md` user guides
are allowed. These checks do not establish that screenshots, binaries, historical
commits or every context-specific identifier are safe to publish. Review them
separately. Never rewrite published Git history as part of routine cleanup.

Public source readiness, application release readiness and device acceptance are
separate conclusions. Passing documentation checks does not prove application
behavior or authorize publication.
