path = require 'path'
fs = require 'fs-plus'
temp = require 'temp'
express = require 'express'
http = require 'http'
wrench = require 'wrench'
apm = require '../lib/apm-cli'
nodeVersion = require('./config.json').nodeVersion

apmRun = (args, callback) ->
  ran = false
  apm.run args, -> ran = true
  waitsFor "waiting for apm #{args.join(' ')}", 60000, -> ran
  runs callback

describe "apm upgrade", ->
  [atomApp, atomHome, packagesDir, server] = []

  beforeEach ->
    spyOnToken()
    silenceOutput()

    atomHome = temp.mkdirSync('apm-home-dir-')
    process.env.ATOM_HOME = atomHome

    app = express()
    app.get '/packages/test-module', (request, response) ->
      response.sendFile path.join(__dirname, 'fixtures', 'upgrade-test-module.json')
    app.get '/packages/multi-module', (request, response) ->
      response.sendFile path.join(__dirname, 'fixtures', 'upgrade-multi-version.json')
    app.get '/packages/different-repo', (request, response) ->
      response.sendFile path.join(__dirname, 'fixtures', 'upgrade-different-repo.json')
    server =  http.createServer(app)

    live = false
    server.listen 3000, '127.0.0.1', ->
      atomHome = temp.mkdirSync('apm-home-dir-')
      atomApp = temp.mkdirSync('apm-app-dir-')
      packagesDir = path.join(atomHome, 'packages')
      process.env.ATOM_HOME = atomHome
      process.env.ATOM_ELECTRON_URL = "http://localhost:3000/node"
      process.env.ATOM_PACKAGES_URL = "http://localhost:3000/packages"
      process.env.ATOM_ELECTRON_VERSION = nodeVersion
      process.env.ATOM_RESOURCE_PATH = atomApp

      fs.writeFileSync(path.join(atomApp, 'package.json'), JSON.stringify(version: '0.10.0'))
      live = true
    waitsFor -> live

  afterEach ->
    done = false
    server.close -> done = true
    waitsFor -> done

  it "does not display updates for unpublished packages", ->
    fs.writeFileSync(path.join(packagesDir, 'not-published', 'package.json'), JSON.stringify({name: 'not-published', version: '1.0', repository: 'https://github.com/a/b'}))

    callback = jasmine.createSpy('callback')
    apm.run(['upgrade', '--list', '--no-color'], callback)

    waitsFor 'waiting for upgrade to complete', 600000, ->
      callback.callCount > 0

    runs ->
      expect(console.log).toHaveBeenCalled()
      expect(console.log.argsForCall[1][0]).toContain 'empty'

  it "does not display updates for packages whose engine does not satisfy the installed Atom version", ->
    fs.writeFileSync(path.join(packagesDir, 'test-module', 'package.json'), JSON.stringify({name: 'test-module', version: '0.3.0', repository: 'https://github.com/a/b'}))

    callback = jasmine.createSpy('callback')
    apm.run(['upgrade', '--list', '--no-color'], callback)

    waitsFor 'waiting for upgrade to complete', 600000, ->
      callback.callCount > 0

    runs ->
      expect(console.log).toHaveBeenCalled()
      expect(console.log.argsForCall[1][0]).toContain 'empty'

  it "displays the latest update that satisfies the installed Atom version", ->
    fs.writeFileSync(path.join(packagesDir, 'multi-module', 'package.json'), JSON.stringify({name: 'multi-module', version: '0.1.0', repository: 'https://github.com/a/b'}))

    callback = jasmine.createSpy('callback')
    apm.run(['upgrade', '--list', '--no-color'], callback)

    waitsFor 'waiting for upgrade to complete', 600000, ->
      callback.callCount > 0

    runs ->
      expect(console.log).toHaveBeenCalled()
      expect(console.log.argsForCall[1][0]).toContain 'multi-module 0.1.0 -> 0.3.0'

  it "does not display updates for packages already up to date", ->
    fs.writeFileSync(path.join(packagesDir, 'multi-module', 'package.json'), JSON.stringify({name: 'multi-module', version: '0.3.0', repository: 'https://github.com/a/b'}))

    callback = jasmine.createSpy('callback')
    apm.run(['upgrade', '--list', '--no-color'], callback)

    waitsFor 'waiting for upgrade to complete', 600000, ->
      callback.callCount > 0

    runs ->
      expect(console.log).toHaveBeenCalled()
      expect(console.log.argsForCall[1][0]).toContain 'empty'

  it "does display updates when the installed package's repository is not the same as the available package's repository", ->
    fs.writeFileSync(path.join(packagesDir, 'different-repo', 'package.json'), JSON.stringify({name: 'different-repo', version: '0.3.0', repository: 'https://github.com/world/hello'}))

    callback = jasmine.createSpy('callback')
    apm.run(['upgrade', '--list', '--no-color'], callback)

    waitsFor 'waiting for upgrade to complete', 600000, ->
      callback.callCount > 0

    runs ->
      expect(console.log).toHaveBeenCalled()
      expect(console.log.argsForCall[1][0]).toContain 'different-repo 0.3.0 -> 0.4.0'

  it "allows the package names to upgrade to be specified", ->
    fs.writeFileSync(path.join(packagesDir, 'multi-module', 'package.json'), JSON.stringify({name: 'multi-module', version: '0.1.0', repository: 'https://github.com/a/b'}))
    fs.writeFileSync(path.join(packagesDir, 'different-repo', 'package.json'), JSON.stringify({name: 'different-repo', version: '0.3.0', repository: 'https://github.com/world/hello'}))

    callback = jasmine.createSpy('callback')
    apm.run(['upgrade', '--list', '--no-color', 'different-repo'], callback)

    waitsFor 'waiting for upgrade to complete', 600000, ->
      callback.callCount > 0

    runs ->
      expect(console.log.callCount).toBe 2
      expect(console.log.argsForCall[0][0]).not.toContain 'multi-module 0.1.0 -> 0.3.0'
      expect(console.log.argsForCall[1][0]).toContain 'different-repo 0.3.0 -> 0.4.0'
      expect(console.log.argsForCall[1][0]).not.toContain 'multi-module 0.1.0 -> 0.3.0'

  it "does not display updates when the installed package's repository does not exist", ->
    fs.writeFileSync(path.join(packagesDir, 'different-repo', 'package.json'), JSON.stringify({name: 'different-repo', version: '0.3.0'}))

    callback = jasmine.createSpy('callback')
    apm.run(['upgrade', '--list', '--no-color'], callback)

    waitsFor 'waiting for upgrade to complete', 600000, ->
      callback.callCount > 0

    runs ->
      expect(console.log).toHaveBeenCalled()
      expect(console.log.argsForCall[1][0]).toContain 'empty'

  it "logs an error when the installed location of Atom cannot be found", ->
    process.env.ATOM_RESOURCE_PATH = '/tmp/atom/is/not/installed/here'
    callback = jasmine.createSpy('callback')
    apm.run(['upgrade', '--list', '--no-color'], callback)

    waitsFor 'waiting for upgrade to complete', 600000, ->
      callback.callCount > 0

    runs ->
      expect(console.error).toHaveBeenCalled()
      expect(console.error.argsForCall[0][0]).toContain 'Could not determine current Atom version installed'

  it "ignores the commit SHA suffix in the version", ->
    fs.writeFileSync(path.join(atomApp, 'package.json'), JSON.stringify(version: '0.10.0-deadbeef'))
    fs.writeFileSync(path.join(packagesDir, 'multi-module', 'package.json'), JSON.stringify({name: 'multi-module', version: '0.1.0', repository: 'https://github.com/a/b'}))

    callback = jasmine.createSpy('callback')
    apm.run(['upgrade', '--list', '--no-color'], callback)

    waitsFor 'waiting for upgrade to complete', 600000, ->
      callback.callCount > 0

    runs ->
      expect(console.log).toHaveBeenCalled()
      expect(console.log.argsForCall[1][0]).toContain 'multi-module 0.1.0 -> 0.3.0'

  describe "for outdated git packages", ->
    [pkgJsonPath] = []

    beforeEach ->
      delete process.env.ATOM_ELECTRON_URL
      delete process.env.ATOM_PACKAGES_URL
      process.env.ATOM_ELECTRON_VERSION = "0.22.0"

      gitRepo = path.join(__dirname, "fixtures", "test-git-repo.git")
      cloneUrl = "file://#{gitRepo}"

      apmRun ["install", cloneUrl], ->
        pkgJsonPath = path.join(process.env.ATOM_HOME, 'packages', 'test-git-repo', 'package.json')
        json = JSON.parse(fs.readFileSync(pkgJsonPath), 'utf8')
        json.apmInstallSource.sha = 'abcdef1234567890'
        fs.writeFileSync pkgJsonPath, JSON.stringify(json)

    it 'shows an upgrade plan', ->
      apmRun ['upgrade', '--list', '--no-color'], ->
        text = console.log.argsForCall.map((arr) -> arr.join(' ')).join("\n")
        expect(text).toMatch /Available \(1\).*\n.*test-git-repo abcdef12 -> 8ae43234/

    it 'updates to the latest sha', ->
      apmRun ['upgrade', '-c', 'false', 'test-git-repo'], ->
        json = JSON.parse(fs.readFileSync(pkgJsonPath), 'utf8')
        expect(json.apmInstallSource.sha).toBe '8ae432341ac6708aff9bb619eb015da14e9d0c0f'

  describe "for outdated git packages (when HEAD points to main)", ->
    [pkgJsonPath] = []

    beforeEach ->
      delete process.env.ATOM_ELECTRON_URL
      delete process.env.ATOM_PACKAGES_URL
      process.env.ATOM_ELECTRON_VERSION = "0.22.0"

      gitRepo = path.join(__dirname, "fixtures", "test-git-repo-with-main.git")
      cloneUrl = "file://#{gitRepo}"

      apmRun ["install", cloneUrl], ->
        pkgJsonPath = path.join(process.env.ATOM_HOME, 'packages', 'test-git-repo-with-main', 'package.json')
        json = JSON.parse(fs.readFileSync(pkgJsonPath), 'utf8')
        json.apmInstallSource.sha = 'abcdef1234567890'
        fs.writeFileSync pkgJsonPath, JSON.stringify(json)

    it 'shows an upgrade plan', ->
      apmRun ['upgrade', '--list', '--no-color'], ->
        text = console.log.argsForCall.map((arr) -> arr.join(' ')).join("\n")
        expect(text).toMatch /Available \(1\).*\n.*test-git-repo-with-main abcdef12 -> c81278af/

    it 'updates to the latest sha', ->
      apmRun ['upgrade', '-c', 'false', 'test-git-repo-with-main'], ->
        json = JSON.parse(fs.readFileSync(pkgJsonPath), 'utf8')
        expect(json.apmInstallSource.sha).toBe 'c81278af71de6c12ce0bc02936d5c1eb22aadaf9'
