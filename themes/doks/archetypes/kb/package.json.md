{
  "name": "@zerobias-org/kb-{{ getenv "HUGO_NAME" }}",
  "version": "0.1.0",
  "description": "{{ getenv "HUGO_DESCRIPTION" }}",
  "author": "{{ getenv "HUGO_AUTHOR" }}",
  "license": "ISC",
  "main": "index.md",
  "repository": {
    "type": "git",
    "url": "git@github.com:zerobias-org/kb.git",
    "directory": "package/{{ getenv "HUGO_NAME" }}"
  },
  "publishConfig": {
    "registry": "https://npm.pkg.github.com/"
  },
  "files": [
    "images/**",
    "index.yml",
    "_index.md",
    "index.md", 
    "README.md"
  ],
  "scripts": {
    "build": "hugo --source \"$(git rev-parse --show-toplevel)\" --contentDir \"$(pwd)\" --destination \"$(pwd)/public\"",
    "clean": "rm -rf public",
    "start": "hugo server --disableFastRender --source $(git rev-parse --show-toplevel) --contentDir $(pwd)",
    "test": "npm run build",
    "test:integration": "dataloader"
  },
  "auditmation": {
    "package": "auditmation.{{ getenv "HUGO_CODE" }}.kb",
    "import-artifact": "kb",
    "dataloader-version": "0.5.4"
  }
}
