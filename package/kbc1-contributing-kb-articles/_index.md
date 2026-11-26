---
code: kbc1
title: "Contribute a Community KB Article"
description: "How to add an article to the ZeroBias community knowledge base: where the articles live, how they are numbered, and the steps from scaffold to published"
type: "kb"
application: learning_center
keywords: [kbc1, community, contribute, contributing, knowledge-base, kb, article, open-source, zerobias-org, hugo, markdown]
relatesTo: []
date: '2026-11-26T00:00:00.000Z'
lastmod: '2026-11-26T00:00:00.000Z'
kbType: guide
draft: false
images: []
weight: 100
---

Community knowledge base articles are open source. Anyone can propose one with a
pull request. This article shows where the articles live and how to add your own.

## Where the articles live

All community articles are in the public repository
[zerobias-org/kb](https://github.com/zerobias-org/kb), one directory per article:

```
package/
└── kbc1-contributing-kb-articles/
    ├── _index.md           the article (Markdown with front matter)
    ├── package.json        npm package metadata
    ├── build.gradle.kts    one-line build marker
    ├── .npmrc              registry configuration
    └── gate-stamp.json     proof that the article passed validation
```

## How articles are numbered

Each article has a short code. The code is the first part of the directory name,
and readers use it to find and link to the article.

| Code | Example | Meaning |
|------|---------|---------|
| `kbc<N>` | `kbc1` | Community article, from `zerobias-org/kb` |
| `kb<N>` | `kb9` | Article written by ZeroBias |
| `ct<name>` | `ctgithubgithub` | "Connect to" guide, generated from a module |

Rules for a community article:

- The code is `kbc` followed by a number. Use the next free number: look at the
  highest `package/kbc*` directory and add one.
- The directory is `<code>-<slug>`, for example `kbc2-my-first-article`. Use
  lowercase letters, digits and hyphens in the slug.
- The code never changes after the article is published. Links depend on it.

## Add an article

### 1. Scaffold

Fork and clone the repository, create a branch, then run the scaffold script with
your directory name and a one-sentence description:

```bash
./scripts/new.sh kbc2-my-first-article "What the reader learns from this article"
```

The script creates the directory with the four files shown above. It stops if the
prefix is not `kbc` or if the number is already in use. It needs
[Hugo](https://gohugo.io/installation/) (extended edition) on your machine.

### 2. Write

Edit `package/kbc2-my-first-article/_index.md`. The block between the `---` lines
is the front matter:

| Field | What to put there |
|-------|-------------------|
| `code` | Your code, for example `kbc2`. It must equal the directory prefix. |
| `title` | The article title |
| `description` | One sentence. It is shown in search results. |
| `keywords` | Words a reader would search for |
| `relatesTo` | Leave as `[]` unless a maintainer asks for a value |

Write the article below the front matter in Markdown. Start your headings at `##`,
because the title is the page heading. Put images in an `images/` directory next
to `_index.md`.

### 3. Validate

Run the gate for your article from the repository root:

```bash
zbb :kbc2-my-first-article:gate
```

The gate checks that the directory name, the `code` and the package name agree,
that no other article uses your code, and that the platform can load the article.
When it passes, it writes `gate-stamp.json` into your article directory.

The gate needs the `zbb` command line tool and access to the ZeroBias package
registry. If you do not have them, open the pull request without the stamp and
say so in the description. A maintainer will run the gate for you.

### 4. Open a pull request

Commit your article directory, including `gate-stamp.json`, and open a pull
request against `main`. Use a commit message such as
`feat(kbc2): add my first article`.

## What happens after the merge

When a maintainer merges your pull request, the repository publishes the article
automatically. It becomes available in the ZeroBias Learning Center under its
code. You do not need to do anything else.

## Change an existing article

Edit its `_index.md`, increase the `version` in its `package.json`, run the gate
again, and open a pull request. Do not rename the directory or change the `code`.
