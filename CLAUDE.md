# CLAUDE.md - Community Knowledge Base Repository

This file provides guidance to Claude Code (claude.ai/code) when working with knowledge base content in this repository.

## Project Overview

This is the **ZeroBias Community Knowledge Base Repository** containing open-source documentation articles, guides, and tutorials. Knowledge base articles provide searchable, categorized documentation for platform features, compliance concepts, and best practices.

**Repository Role:** Community-contributed documentation and knowledge base articles

This repository follows the same structure as `auditlogic/kb` but contains community-contributed, open-source documentation.

## Current Status

⚠️ **AI-Assisted Development Workflows Needed**

This CLAUDE.md is a placeholder. Comprehensive AI-assisted development workflows for creating and maintaining KB articles are planned but not yet implemented.

**What's Needed:**
- Step-by-step workflows for creating new KB articles
- Hugo static site generator usage
- Markdown authoring guidelines
- Category and tag organization
- Search optimization
- Publishing and versioning workflows

## Repository Structure

```
kb/
├── package/zerobias/          # Community KB article packages
│   └── <article-id>/          # Individual KB article
│       ├── package.json       # NPM package configuration
│       ├── _index.md          # Hugo article content (Markdown)
│       ├── images/            # Article images
│       ├── CHANGELOG.md       # Version history
│       └── npm-shrinkwrap.json
├── scripts/                   # Build and publishing scripts
├── lerna.json                 # Monorepo configuration
└── README.md
```

## File Format Reference

**Source of Truth:** `../../com/platform/dataloader/src/processors/kb/`

**Expected Structure:**
- `_index.md` - Hugo-formatted Markdown with frontmatter
- `package.json` - Must include `auditmation.import-artifact: "kb"`
- `images/` - Article images and screenshots

## KB Article Structure

### Hugo Frontmatter (_index.md)

```markdown
---
title: "How to Configure Multi-Factor Authentication"
description: "Step-by-step guide for enabling MFA on your account"
date: 2025-11-11
categories:
  - Security
  - Authentication
tags:
  - mfa
  - 2fa
  - security
  - best-practices
weight: 10
draft: false
---

# How to Configure Multi-Factor Authentication

Multi-factor authentication (MFA) adds an extra layer of security...

## Prerequisites

- Active user account
- Mobile device with authenticator app

## Steps

1. Navigate to Settings > Security
2. Click "Enable MFA"
3. Scan QR code with authenticator app
4. Enter verification code
5. Save backup codes

## Troubleshooting

...
```

### Categories

Common KB article categories:
- Getting Started
- Security
- Compliance
- Integration
- API Documentation
- Troubleshooting
- Best Practices

## Integration with Platform

### Dataloader Integration
**Handler Location:** `../../com/platform/dataloader/src/processors/kb/`
**Database Table:** `catalog.kb_article`

### Hugo Build Process
1. KB articles written in Markdown
2. Hugo builds static HTML site
3. Deployed to S3/CloudFront
4. Searchable via platform portal

### Usage in Platform
- **Help Documentation:** Contextual help links in UI
- **Search:** Full-text search across all articles
- **Category Browse:** Organized by topic and category
- **API Reference:** Technical documentation

## Related Documentation

- **[Root CLAUDE.md](../../CLAUDE.md)** - Meta-repo guidance
- **[ContentArtifacts.md](../../ContentArtifacts.md)** - Content catalog system
- **[auditlogic/kb/CLAUDE.md](../../auditlogic/kb/CLAUDE.md)** - Proprietary KB articles (comprehensive documentation)
- **[com/platform/dataloader/CLAUDE.md](../../com/platform/dataloader/CLAUDE.md)** - Dataloader processor
- **[Hugo Documentation](https://gohugo.io/)** - Static site generator

## Important Notes

### Community vs Proprietary

**This Repository (zerobias-org/kb):**
- Open-source, community-contributed documentation
- Public GitHub repository
- MIT/Apache license
- Community edits and translations

**Proprietary Repository (auditlogic/kb):**
- Official platform documentation
- Private GitHub repository
- Commercial license
- Professional technical writing

Both follow identical structure and use same Hugo/dataloader workflow.

### Hugo Static Site Generator

KB articles use Hugo for:
- Markdown-based authoring
- Template-driven rendering
- Fast static site generation
- Multi-language support
- Built-in search

### Markdown Best Practices

1. **Clear headings:** Use H2-H4 hierarchy
2. **Code blocks:** Use fenced code blocks with language
3. **Images:** Store in `images/` directory with descriptive names
4. **Links:** Use relative links for internal docs
5. **Frontmatter:** Always include title, description, categories, tags

## Future Development

Once AI-assisted development workflows are implemented, this CLAUDE.md will include:
- Creating new KB article from template
- Hugo site structure and configuration
- Markdown authoring best practices
- Image optimization and management
- Building and previewing locally
- Publishing to NPM registry
- Integration with platform search

---

**Last Updated:** 2025-11-11
**Maintainers:** ZeroBias Community

