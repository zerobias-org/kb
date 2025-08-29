const { LambdaClient, InvokeCommand } = require("@aws-sdk/client-lambda");
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync, spawnSync } = require('child_process');
const { randomUUID } = require('crypto');

const repository = `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}`;
const actionRunUrl = `${repository}/actions/runs/${process.env.GITHUB_RUN_ID}`;
const codePrefix = process.env.CODE_PREFIX || 'ct';
const cdnRoot = `https://cdn.zerobias.com/${codePrefix}`;
const s3Uri = `s3://auditmation-cdn/${codePrefix}`;
const titlePrefix = process.env.TITLE_PREFIX || 'Connect to'
const tagOnly = process.env.TAG_ONLY !== undefined && process.env.TAG_ONLY === 'true';
console.log('TAG ONLY', tagOnly);
console.log('TAG ONLY', process.env.TAG_ONLY);

if (tagOnly) {
  console.info('Starting job for tagging only');
} else {
  console.info('Starting publish job');
}

const npmrc = `
@auditmation:registry=https://pkg.zerobias.org
@auditlogic:registry=https://pkg.zerobias.org
@zerobias-org:registry=https://pkg.zerobias.org
//pkg.zerobias.org/:_authToken=\${ZB_TOKEN}
`;

function copyAndReplaceFunc(pkgDir) {
  /* Substitutions:
   * - __PACKAGE_NAME__
   * - __VERSION__
   * - __DESCRIPTION__
   * - __DATALOADER_PACKAGE__ (eg auditmation.kb.kbfoo)
   * - __CONTENT_PACKAGE__
   * - __CONTENT_VERSION__
   * - __CODE__
   * - __MODULE_ID__
   * - __TIMESTAMP__
   */

  const pkgJson = JSON.parse(fs.readFileSync(path.join(pkgDir, 'package.json')));
  const { name, version, description, moduleId } = pkgJson;

  let [pkgScope, pkgName] = name.split('/');
  pkgName = pkgName.replace('module-', '');
  const code = `${codePrefix}${pkgName.replace(/-/g, '')}`;
  pkgName = `kb-${codePrefix}-${pkgName}`;

  return (fileName, destPath) => {
    const f = fs.readFileSync(path.join(__dirname, '..', 'resources', fileName));
    let str = f.toString();
    str = str.replace(/__PACKAGE_NAME__/g, `${pkgScope}/${pkgName}`);
    str = str.replace(/__VERSION__/g, `${version}`);
    str = str.replace(/__DESCRIPTION__/g, `${description}`);
    str = str.replace(/__DATALOADER_PACKAGE__/g, `zerobias-org.${pkgName}.kb`);
    str = str.replace(/__CONTENT_PACKAGE__/g, `${name}`);
    str = str.replace(/__CONTENT_VERSION__/g, `${version}`);
    str = str.replace(/__CODE__/g, `${code}`);
    str = str.replace(/__MODULE_ID__/g, `${moduleId}`);
    str = str.replace(/__TIMESTAMP__/g, `${new Date().toISOString()}`);
    str = str.replace(/__CODE_PREFIX__/g, `${codePrefix}`);
    str = str.replace(/__TITLE_PREFIX__/g, `${titlePrefix}`);
    console.info(`Writing file ${fileName}:\n${str}`);
    fs.writeFileSync(destPath, str);
    return code;
  }
}

async function publishReleaseEvent(kbDir) {
  const pkgJson = JSON.parse(fs.readFileSync(path.join(kbDir, 'package.json'), 'utf-8'));
  const {
    name,
    version,
    auditmation,
  } = pkgJson;
  console.info(`Sending event for ${name}@${version}`);

  const distTags = JSON.parse(execSync(`npm view ${name}@${version} dist-tags --json`, {
    env: {
      ...process.env,
      ZB_TOKEN: process.env.ZB_TOKEN
    }
  }));

  const message = {
    body: {
      id: randomUUID(),
      service: 'release',
      eventType: 'release',
      name,
      version,
      repository,
      actionRunUrl,
      auditmation,
      distTags,
    },
  };

  console.info(`Sending release event: ${JSON.stringify(message, null, 2)}`);
  const command = new InvokeCommand({
    FunctionName: 'auditmation-event-router-events',
    Payload: Buffer.from(JSON.stringify(message)),
  })
  const client = new LambdaClient({});
  await client.send(command);
}

async function main() {
  // get arguments
  let [, pkgName, pkgVersion] = process.argv[2].split('@');
  pkgName = `@${pkgName}`;
  console.info(`Creating KB Article for ${pkgName}@${pkgVersion}`);

  const execOptions = { stdio: 'inherit' };
  execOptions.env = {
    ...process.env,
    ZB_TOKEN: process.env.ZB_TOKEN
  };

  const distTags = JSON.parse(execSync(`npm view ${pkgName}@${pkgVersion} dist-tags --json`, {
    env: {
      ...process.env,
      ZB_TOKEN: process.env.ZB_TOKEN
    }
  }));
  console.info(`Found dist tags ${JSON.stringify(distTags, null, 2)}`);

  // install target module to extract API
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'zerobiasorg-'));
  execOptions.cwd = tmpDir;
  console.info(`Created temporary directory ${tmpDir}`);

  // copy in the npmrc
  fs.writeFileSync(path.join(tmpDir, '.npmrc'), npmrc);
  console.info(`Directory listing for ${tmpDir}: ${fs.readdirSync(tmpDir)}`);

  // download the package
  spawnSync('npm', ['pack', '--silent', `${pkgName}@${pkgVersion}`], execOptions);
  console.info(`Directory listing for ${tmpDir}: ${fs.readdirSync(tmpDir)}`);

  // find and extract the package
  const tarballName = fs.readdirSync(tmpDir).find((f) => f.endsWith('.tgz'));
  console.info(`Extracting tarball ${tarballName}`);
  spawnSync('tar', ['xf', tarballName], execOptions);

  const pkgDir = path.join(tmpDir, 'package');
  console.info(`Directory listing for ${pkgDir}: ${fs.readdirSync(pkgDir)}`);

  const kbDir = path.join(process.cwd(), 'generated', pkgName);
  fs.mkdirSync(kbDir, { recursive: true });
  console.info(`Generating article in ${kbDir}`);

  const copyAndReplace = copyAndReplaceFunc(pkgDir);
  fs.writeFileSync(path.join(kbDir, '.npmrc'), npmrc);

  const contentFile = fs.existsSync(path.join(pkgDir, 'USERGUIDE.md'))
    ? path.join(pkgDir, 'USERGUIDE.md') : path.join(pkgDir, 'README.md');
  const code = copyAndReplace('_index.md', path.join(kbDir, '_index.md'));
  const content = fs.readFileSync(contentFile, 'utf8');
  fs.appendFileSync(path.join(kbDir, '_index.md'), content);

  copyAndReplace('package.json', path.join(kbDir, 'package.json'));

  const resourceDir = path.join(pkgDir, 'resources');
  if (fs.existsSync(resourceDir)) {
    fs.mkdirSync(path.join(kbDir, 'resources'), { recursive: true });
    const resources = fs.readdirSync(path.join(pkgDir, 'resources'));
    for (file of resources) {
      fs.copyFileSync(path.join(pkgDir, 'resources', file), path.join(kbDir, 'resources', file));
    }
  }
  console.info(`Directory listing for ${kbDir}: ${fs.readdirSync(kbDir)}`);

  // install, build, and publish
  execOptions.cwd = kbDir;
  console.info('Running npm install');
  spawnSync('npm', ['install'], execOptions);
  spawnSync('npm', ['shrinkwrap'], execOptions);

  console.info('Running build');
  const dataDir = path.join(process.cwd(), 'data');
  if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir, { recursive: true });
  }
  fs.writeFileSync(path.join(dataDir, 'kb.json'), JSON.stringify({ code }));
  spawnSync('npm', ['run', 'build', '--', '-b', `${cdnRoot}/${code}`], execOptions);

  if (!tagOnly) {
    console.info('Running npm publish');
    execOptions.env = {
      ...process.env,
      ZB_TOKEN: process.env.ZB_TOKEN
    };
    const publishTag = distTags['latest'] === pkgVersion ? 'latest' : 'dev';
    const out = spawnSync('npm', ['publish', '--tag', publishTag], execOptions);

    if (out.status !== 0) {
      console.error(out.error);
      process.exit(out.status);
    }
  }

  const pkgJson = JSON.parse(fs.readFileSync(path.join(pkgDir, 'package.json')));
  const { name } = pkgJson;
  let [pkgScope, kbPkgName] = name.split('/');
  kbPkgName = kbPkgName.replace('module-', '');
  kbPkgName = `kb-${codePrefix}-${kbPkgName}`;
  console.info(`Checking dist tags for ${pkgScope}/${kbPkgName}@${pkgVersion}`);
  execOptions.env = {
    ...process.env,
    ZB_TOKEN: process.env.ZB_TOKEN
  };
  for (let tag in distTags) {
    if (distTags[tag] === pkgVersion) {
      console.info(`Dist tag: ${tag} version matches, uploading to cdn`);
      console.info('Running build');
      spawnSync('npm', ['run', 'clean'], execOptions);
      spawnSync('npm', ['dist-tag', 'add', `${pkgScope}/${kbPkgName}@${pkgVersion}`, tag], execOptions);
      if (tag === 'latest') {
        spawnSync('npm', ['run', 'build', '--', '-b', `${cdnRoot}/${code}`], execOptions);
        spawnSync('aws', ['s3', 'sync', 'public', `${s3Uri}/${code}`], execOptions);
      } else {
        spawnSync('npm', ['run', 'build', '--', '-b', `${cdnRoot}/${tag}/${code}`], execOptions);
        spawnSync('aws', ['s3', 'sync', 'public', `${s3Uri}/${tag}/${code}`], execOptions);
      }
    } else {
      console.info(`Dist tag: ${tag} version does not match, skipping`);
    }
  }

  await publishReleaseEvent(kbDir);
}

main();
