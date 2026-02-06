/* eslint-disable */
import { execSync } from 'child_process';
import * as fs from 'fs';
import * as _ from 'lodash';
import * as path from 'path';
import * as Generator from 'yeoman-generator';
import yosay = require('yosay');

const debug = require('debug')('generator-gflif');
const { version } = require('../../package.json');

let hasYarn = false;
try {
  execSync('yarn -v', { stdio: 'ignore' });
  hasYarn = true;
} catch {}

export default class CLI extends Generator {
  options: {
    defaults?: boolean;
    force: boolean;
    yarn: boolean;
  };

  name: string;

  pjson!: any;

  answers!: {
    name: string;
    bin: string;
    description: string;
    version: string;
    author: string;
    files: string;
    license: string;
    pkg: string;
    typescript: boolean;
    mocha: boolean;
  };

  yarn!: boolean;

  repository?: string;

  constructor(args: string | string[], opts: Generator.GeneratorOptions) {
    super(args, opts);

    this.name = opts.name;
    this.options = {
      defaults: opts.defaults,
      force: opts.force,
      yarn: hasYarn,
    };
  }

  async prompting(): Promise<void> {
    const msg = __('buildMessage');

    this.log(yosay(`${msg} ${__('version')}: ${version}`));

    execSync(`git clone https://git.woa.com/code/hello-cli.git "${path.resolve(this.name)}"`);
    fs.rmSync(`${path.resolve(this.name, '.git')}`, { recursive: true });

    this.destinationRoot(path.resolve(this.name));
    this.env.cwd = this.destinationPath();

    // establish order of properties in the resulting package.json
    this.pjson = {
      name: '',
      version: '',
      description: '',
      author: '',
      bin: {},
      homepage: '',
      license: '',
      main: '',
      repository: '',
      files: [],
      dependencies: {},
      devDependencies: {},
      oclif: {},
      scripts: {},
      engines: {},
      ...(this.fs.readJSON(path.join(this.env.cwd, 'package.json'), {}) as Record<string, unknown>),
    };
    const repository = this.destinationRoot().split(path.sep).slice(-2).join('/');
    const defaults = {
      ...this.pjson,
      name: this.name ? this.name.replace(/ /g, '-') : this.determineAppname().replace(/ /g, '-'),
      version: '0.0.0',
      license: 'MIT',
      author: this.user.git.name(),
      dependencies: {},
      repository,
      engines: {
        node: '>=14.0.0',
        ...this.pjson.engines,
      },
      options: this.options,
    };
    this.repository = defaults.repository;
    if (this.repository && (this.repository as any).url) {
      this.repository = (this.repository as any).url;
    }

    if (this.options.defaults) {
      this.answers = defaults;
    } else {
      this.answers = (await this.prompt([
        {
          type: 'input',
          name: 'name',
          message: __('packageName'),
          default: defaults.name,
        },
        {
          type: 'input',
          name: 'bin',
          message: __('commandName'),
          default: (answers: any) => answers.name,
        },
        {
          type: 'input',
          name: 'description',
          message: __('description'),
          default: defaults.description,
        },
        {
          type: 'input',
          name: 'author',
          message: __('author'),
          default: defaults.author,
        },
        {
          type: 'input',
          name: 'version',
          message: __('version'),
          default: defaults.version,
          when: !this.pjson.version,
        },
        {
          type: 'input',
          name: 'license',
          message: __('license'),
          default: defaults.license,
        },
        {
          type: 'list',
          name: 'pkg',
          message: __('selectPackageManager'),
          choices: [
            { name: 'npm', value: 'npm' },
            { name: 'yarn', value: 'yarn' },
          ],
          default: () => (this.options.yarn || hasYarn ? 1 : 0),
        },
      ])) as any;
    }

    debug(this.answers);
    if (!this.options.defaults) {
      this.options = {
        yarn: this.answers.pkg === 'yarn',
        force: true,
      };
    }

    this.yarn = this.options.yarn;
    this.env.options.nodePackageManager = this.yarn ? 'yarn' : 'npm';

    this.pjson.name = this.answers.name || defaults.name;
    this.pjson.description = this.answers.description || defaults.description;
    this.pjson.version = this.answers.version || defaults.version;
    this.pjson.engines.node = defaults.engines.node;
    this.pjson.author = this.answers.author || defaults.author;
    this.pjson.files = this.answers.files || defaults.files || '/lib';
    this.pjson.license = this.answers.license || defaults.license;
    // eslint-disable-next-line no-multi-assign
    this.repository = this.pjson.repository = defaults.repository;

    this.pjson.homepage = this.repository;
    this.pjson.bugs = `${this.repository}/issues`;

    this.pjson.oclif.bin = this.answers.bin;
    this.pjson.oclif.dirname = this.answers.bin;
    this.pjson.bin = {};
    this.pjson.bin[this.pjson.oclif.bin] = './bin/run';
  }

  writing(): void {
    if (this.pjson.oclif && Array.isArray(this.pjson.oclif.plugins)) {
      this.pjson.oclif.plugins.sort();
    }

    if (_.isEmpty(this.pjson.oclif)) delete this.pjson.oclif;
    this.pjson.files = _.uniq((this.pjson.files || []).sort());
    this.fs.writeJSON(this.destinationPath('./package.json'), this.pjson);

    this.fs.write(this.destinationPath('.gitignore'), this._gitignore());
  }

  end(): void {
    this.spawnCommandSync(this.env.options.nodePackageManager, ['run', 'build']);
    this.spawnCommandSync(path.join(this.env.cwd, 'node_modules', '.bin', 'oclif'), ['readme'], { cwd: this.env.cwd });
    console.log(`\n${__('createSuccess')} ${this.pjson.name} ${__('in')} ${this.destinationRoot()}`);
  }

  private _gitignore(): string {
    const existing = this.fs.exists(this.destinationPath('.gitignore'))
      ? this.fs.read(this.destinationPath('.gitignore')).split('\n')
      : [];
    return (
      _([
        '*-debug.log',
        '*-error.log',
        'node_modules',
        '/tmp',
        '/dist',
        this.yarn ? '/package-lock.json' : '/yarn.lock',
        '/lib',
      ])
        .concat(existing)
        .compact()
        .uniq()
        .sort()
        .join('\n') + '\n'
    );
  }
}
