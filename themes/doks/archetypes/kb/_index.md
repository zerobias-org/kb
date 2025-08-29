---
code: {{ getenv "HUGO_CODE" }}
title: "{{ replace (getenv "HUGO_TITLE") "-" " " | title }}"
description: "{{ getenv "HUGO_DESCRIPTION" }}"
type: "kb"
application: learning_center
keywords: []
relatesTo: []
date: {{ .Date }}
---
