{
  "name": "@zerobias-org/kb-{{ getenv "HUGO_NAME" }}",
  "version": "1.0.0",
  "description": "{{ getenv "HUGO_DESCRIPTION" }}",
  "author": "{{ getenv "HUGO_AUTHOR" }}",
  "license": "ISC",
  "main": "_index.md",
  "repository": {
    "type": "git",
    "url": "git@github.com:zerobias-org/kb.git",
    "directory": "package/{{ getenv "HUGO_NAME" }}"
  },
  "publishConfig": {
    "registry": "https://pkg.zerobias.org"
  },
  "files": [
    "images/**",
    "resources/**",
    "_index.md",
    "README.md",
    "npm-shrinkwrap.json"
  ],
  "scripts": {
    "build": "hugo --source \"$(git rev-parse --show-toplevel)\" --contentDir \"$(pwd)\" --destination \"$(pwd)/public\"",
    "clean": "rm -rf public",
    "start": "hugo server --disableFastRender --source $(git rev-parse --show-toplevel) --contentDir $(pwd)",
    "test": "npm run build"
  },
  "zerobias": {
    "package": "zerobias.{{ getenv "HUGO_CODE" }}.kb",
    "import-artifact": "kb",
    "dataloader-version": "1.0.0"
  }
}
