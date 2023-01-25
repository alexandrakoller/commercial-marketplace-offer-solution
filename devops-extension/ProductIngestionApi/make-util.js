var check = require('validator').default;
var fs = require('fs');
var makeOptions = require('./make-options.json');
var minimatch = require('minimatch');
var ncp = require('child_process');
var os = require('os');
var path = require('path');
var process = require('process');
var semver = require('semver');
var shell = require('shelljs');
var syncRequest = require('sync-request');

// global paths
var downloadPath = path.join(__dirname, '_download');

// list of .NET culture names
var cultureNames = ['cs', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'pl', 'pt-BR', 'ru', 'tr', 'zh-Hans', 'zh-Hant'];

var allowedTypescriptVersions = ['2.3.4', '4.0.2'];

//------------------------------------------------------------------------------
// shell functions
//------------------------------------------------------------------------------
var shellAssert = function () {
    var errMsg = shell.error();
    if (errMsg) {
        throw new Error(errMsg.toString());
    }
}

var cd = function (dir) {
    var cwd = process.cwd();
    if (cwd != dir) {
        console.log('');
        console.log(`> cd ${path.relative(cwd, dir)}`);
        shell.cd(dir);
        shellAssert();
    }
}
exports.cd = cd;

var cp = function (options, source, dest) {
    if (dest) {
        shell.cp(options, source, dest);
    }
    else {
        shell.cp(options, source);
    }

    shellAssert();
}
exports.cp = cp;

var mkdir = function (options, target) {
    if (target) {
        shell.mkdir(options, target);
    }
    else {
        shell.mkdir(options);
    }

    shellAssert();
}
exports.mkdir = mkdir;

var rm = function (options, target) {
    if (target) {
        shell.rm(options, target);
    }
    else {
        shell.rm(options);
    }

    shellAssert();
}
exports.rm = rm;

var test = function (options, p) {
    var result = shell.test(options, p);
    shellAssert();
    return result;
}
exports.test = test;
//------------------------------------------------------------------------------

var assert = function (value, name) {
    if (!value) {
        throw new Error('"' + name + '" cannot be null or empty.');
    }
}
exports.assert = assert;

var banner = function (message, noBracket) {
    console.log();
    if (!noBracket) {
        console.log('------------------------------------------------------------');
    }
    console.log(message);
    if (!noBracket) {
        console.log('------------------------------------------------------------');
    }
}
exports.banner = banner;

var rp = function (relPath) {
    return path.join(shell.pwd() + '', relPath);
}
exports.rp = rp;

var fail = function (message) {
    console.error('ERROR: ' + message);
    process.exit(1);
}
exports.fail = fail;

var ensureExists = function (checkPath) {
    assert(checkPath, 'checkPath');
    var exists = test('-d', checkPath) || test('-f', checkPath);

    if (!exists) {
        fail(checkPath + ' does not exist');
    }
}
exports.ensureExists = ensureExists;

var pathExists = function (checkPath) {
    return test('-d', checkPath) || test('-f', checkPath);
}
exports.pathExists = pathExists;

var copyExtensionResources = function (srcPath, destPath) {
    assert(srcPath, 'srcPath');
    assert(destPath, 'destPath');

    // copy the globally defined set of default task resources
    var toCopy = makeOptions['extensionResources'];
    toCopy.forEach(function (item) {
        matchCopy(item, srcPath, destPath, { noRecurse: true, matchBase: true });
    });
}
exports.copyExtensionResources = copyExtensionResources;

var copyTaskResources = function (taskMake, srcPath, destPath) {
    assert(taskMake, 'taskMake');
    assert(srcPath, 'srcPath');
    assert(destPath, 'destPath');

    // copy the globally defined set of default task resources
    var toCopy = makeOptions['taskResources'];
    toCopy.forEach(function (item) {
        matchCopy(item, srcPath, destPath, { noRecurse: true, matchBase: true });
    });

    // copy the locally defined set of resources
    if (taskMake.hasOwnProperty('cp')) {
        copyGroups(taskMake.cp, srcPath, destPath);
    }

    // remove the locally defined set of resources
    if (taskMake.hasOwnProperty('rm')) {
        removeGroups(taskMake.rm, destPath);
    }
}
exports.copyTaskResources = copyTaskResources;

var matchFind = function (pattern, root, options) {
    assert(pattern, 'pattern');
    assert(root, 'root');

    // create a copy of the options
    var clone = {};
    Object.keys(options || {}).forEach(function (key) {
        clone[key] = options[key];
    });
    options = clone;

    // determine whether to recurse
    var noRecurse = options.hasOwnProperty('noRecurse') && options.noRecurse;
    delete options.noRecurse;

    // normalize first, so we can substring later
    root = path.resolve(root);

    // determine the list of items
    var items;
    if (noRecurse) {
        items = fs.readdirSync(root)
            .map(function (name) {
                return path.join(root, name);
            });
    }
    else {
        items = shell.find(root)
            .filter(function (item) { // filter out the root folder
                return path.normalize(item) != root;
            });
    }

    return minimatch.match(items, pattern, options);
}
exports.matchFind = matchFind;

var matchCopy = function (pattern, sourceRoot, destRoot, options) {
    assert(pattern, 'pattern');
    assert(sourceRoot, 'sourceRoot');
    assert(destRoot, 'destRoot');

    console.log(`copying ${pattern}`);

    // normalize first, so we can substring later
    sourceRoot = path.resolve(sourceRoot);
    destRoot = path.resolve(destRoot);

    matchFind(pattern, sourceRoot, options)
        .forEach(function (item) {
            // create the dest dir based on the relative item path
            var relative = item.substring(sourceRoot.length + 1);
            assert(relative, 'relative'); // should always be filterd out by matchFind
            var dest = path.dirname(path.join(destRoot, relative));
            mkdir('-p', dest);

            cp('-Rf', item, dest + '/');
        });
}
exports.matchCopy = matchCopy;

var run = function (cl, inheritStreams, noHeader) {
    if (!noHeader) {
        console.log();
        console.log('> ' + cl);
    }

    var options = {
        stdio: inheritStreams ? 'inherit' : 'pipe'
    };
    var rc = 0;
    var output;
    try {
        output = ncp.execSync(cl, options);
    }
    catch (err) {
        if (!inheritStreams) {
            console.error(err.output ? err.output.toString() : err.message);
        }

        process.exit(1);
    }

    return (output || '').toString().trim();
}
exports.run = run;

var ensureTool = function (name, versionArgs, validate) {
    console.log(name + ' tool:');
    var toolPath = shell.which(name);
    if (!toolPath) {
        fail(name + ' not found.  might need to run npm install');
    }

    if (versionArgs) {
        var result = shell.exec(name + ' ' + versionArgs);
        if (typeof validate == 'string') {
            if (result.stdout.trim() != validate) {
                fail('expected version: ' + validate);
            }
        }
        else {
            validate(result.stdout.trim());
        }
    }

    console.log(toolPath + '');
}
exports.ensureTool = ensureTool;

var downloadFile = function (url) {
    // validate parameters
    if (!url) {
        throw new Error('Parameter "url" must be set.');
    }

    // skip if already downloaded
    var scrubbedUrl = url.replace(/[/\:?]/g, '_');
    var targetPath = path.join(downloadPath, 'file', scrubbedUrl);
    var marker = targetPath + '.completed';
    if (!test('-f', marker)) {
        console.log('Downloading file: ' + url);

        // delete any previous partial attempt
        if (test('-f', targetPath)) {
            rm('-f', targetPath);
        }

        // download the file
        mkdir('-p', path.join(downloadPath, 'file'));
        var result = syncRequest('GET', url);
        fs.writeFileSync(targetPath, result.getBody());

        // write the completed marker
        fs.writeFileSync(marker, '');
    }

    return targetPath;
}
exports.downloadFile = downloadFile;

var downloadArchive = function (url, omitExtensionCheck) {
    // validate parameters
    if (!url) {
        throw new Error('Parameter "url" must be set.');
    }

    var isZip;
    var isTargz;
    if (omitExtensionCheck) {
        isZip = true;
    }
    else {
        if (url.match(/\.zip$/)) {
            isZip = true;
        }
        else if (url.match(/\.tar\.gz$/) && (process.platform == 'darwin' || process.platform == 'linux')) {
            isTargz = true;
        }
        else {
            throw new Error('Unexpected archive extension');
        }
    }

    // skip if already downloaded and extracted
    var scrubbedUrl = url.replace(/[/\:?]/g, '_');

    var crypto = require('crypto');
    var newScrubbedUrl = crypto.createHash('md5').update(scrubbedUrl).digest('hex');

    var targetPath = path.join(downloadPath, 'archive', newScrubbedUrl);
    var marker = targetPath + '.completed';
    if (!test('-f', marker)) {
        // download the archive
        var archivePath = downloadFile(url);
        console.log('Extracting archive: ' + url);

        // delete any previously attempted extraction directory
        if (test('-d', targetPath)) {
            rm('-rf', targetPath);
        }

        // extract
        mkdir('-p', targetPath);
        if (isZip) {
            if (process.platform == 'win32') {
                let escapedFile = archivePath.replace(/'/g, "''").replace(/"|\n|\r/g, ''); // double-up single quotes, remove double quotes and newlines
                let escapedDest = targetPath.replace(/'/g, "''").replace(/"|\n|\r/g, '');

                let command = `$ErrorActionPreference = 'Stop' ; try { Add-Type -AssemblyName System.IO.Compression.FileSystem } catch { } ; [System.IO.Compression.ZipFile]::ExtractToDirectory('${escapedFile}', '${escapedDest}')`;
                run(`powershell -Command "${command}"`);
            } else {
                run(`unzip ${archivePath} -d ${targetPath}`);
            }
        }
        else if (isTargz) {
            var originalCwd = process.cwd();
            cd(targetPath);
            try {
                run(`tar -xzf "${archivePath}"`);
            }
            finally {
                cd(originalCwd);
            }
        }

        // write the completed marker
        fs.writeFileSync(marker, '');
    }

    return targetPath;
}
exports.downloadArchive = downloadArchive;

var copyGroup = function (group, sourceRoot, destRoot) {
    // example structure to copy a single file:
    // {
    //   "source": "foo.dll"
    // }
    //
    // example structure to copy an array of files/folders to a relative directory:
    // {
    //   "source": [
    //     "foo.dll",
    //     "bar",
    //   ],
    //   "dest": "baz/",
    //   "options": "-R"
    // }
    //
    // example to multiply the copy by .NET culture names supported by TFS:
    // {
    //   "source": "<CULTURE_NAME>/foo.dll",
    //   "dest": "<CULTURE_NAME>/"
    // }
    //

    // validate parameters
    assert(group, 'group');
    assert(group.source, 'group.source');
    if (typeof group.source == 'object') {
        assert(group.source.length, 'group.source.length');
        group.source.forEach(function (s) {
            assert(s, 'group.source[i]');
        });
    }

    assert(sourceRoot, 'sourceRoot');
    assert(destRoot, 'destRoot');

    // multiply by culture name (recursive call to self)
    if (group.dest && group.dest.indexOf('<CULTURE_NAME>') >= 0) {
        cultureNames.forEach(function (cultureName) {
            // culture names do not contain any JSON-special characters, so this is OK (albeit a hack)
            var localizedGroupJson = JSON.stringify(group).replace(/<CULTURE_NAME>/g, cultureName);
            copyGroup(JSON.parse(localizedGroupJson), sourceRoot, destRoot);
        });

        return;
    }

    // build the source array
    var source = typeof group.source == 'string' ? [group.source] : group.source;
    source = source.map(function (val) { // root the paths
        return path.join(sourceRoot, val);
    });

    // create the destination directory
    var dest = group.dest ? path.join(destRoot, group.dest) : destRoot + '/';
    dest = path.normalize(dest);
    mkdir('-p', dest);

    // copy the files
    if (group.hasOwnProperty('options') && group.options) {
        cp(group.options, source, dest);
    }
    else {
        cp(source, dest);
    }
}

var copyGroups = function (groups, sourceRoot, destRoot) {
    assert(groups, 'groups');
    assert(groups.length, 'groups.length');
    groups.forEach(function (group) {
        copyGroup(group, sourceRoot, destRoot);
    })
}
exports.copyGroups = copyGroups;

var removeGroup = function (group, pathRoot) {
    // example structure to remove an array of files/folders:
    // {
    //   "items": [
    //     "foo.dll",
    //     "bar",
    //   ],
    //   "options": "-R"
    // }

    // validate parameters
    assert(group, 'group');
    assert(group.items, 'group.items');
    if (typeof group.items != 'object') {
        throw new Error('Expected group.items to be an array');
    } else {
        assert(group.items.length, 'group.items.length');
        group.items.forEach(function (p) {
            assert(p, 'group.items[i]');
        });
    }

    assert(group.options, 'group.options');
    assert(pathRoot, 'pathRoot');

    // build the rooted items array
    var rootedItems = group.items.map(function (val) { // root the paths
        return path.join(pathRoot, val);
    });

    // remove the items
    rm(group.options, rootedItems);
}

var removeGroups = function (groups, pathRoot) {
    assert(groups, 'groups');
    assert(groups.length, 'groups.length');
    groups.forEach(function (group) {
        removeGroup(group, pathRoot);
    })
}
exports.removeGroups = removeGroups;

var addPath = function (directory) {
    console.log('');
    console.log(`> prepending PATH ${directory}`);

    var separator;
    if (os.platform() == 'win32') {
        separator = ';';
    }
    else {
        separator = ':';
    }

    var existing = process.env['PATH'];
    if (existing) {
        // move directory to top
        if (existing.indexOf(directory) !== -1) {
            existing = existing.replace(directory + separator, '');
        }
        process.env['PATH'] = directory + separator + existing;
    }
    else {
        process.env['PATH'] = directory;
    }
}
exports.addPath = addPath;

var getExternals = function (externals, destRoot) {
    assert(externals, 'externals');
    assert(destRoot, 'destRoot');

    // .zip files
    if (externals.hasOwnProperty('archivePackages')) {
        var archivePackages = externals.archivePackages;
        archivePackages.forEach(function (archive) {
            assert(archive.url, 'archive.url');
            assert(archive.dest, 'archive.dest');

            // download and extract the archive package
            var archiveSource = downloadArchive(archive.url);

            // copy the files
            var archiveDest = path.join(destRoot, archive.dest);
            mkdir('-p', archiveDest);
            cp('-R', path.join(archiveSource, '*'), archiveDest);
        });
    }

    // external NuGet V2 packages
    if (externals.hasOwnProperty('nugetv2')) {
        var nugetPackages = externals.nugetv2;
        nugetPackages.forEach(function (package) {
            // validate the structure of the data
            assert(package.name, 'package.name');
            assert(package.version, 'package.version');
            assert(package.repository, 'package.repository');
            assert(package.cp, 'package.cp');
            assert(package.cp, 'package.cp.length');

            // download and extract the NuGet V2 package
            var url = package.repository.replace(/\/$/, '') + '/package/' + package.name + '/' + package.version;
            var packageSource = downloadArchive(url, /*omitExtensionCheck*/true);

            // copy specific files
            copyGroups(package.cp, packageSource, destRoot);
        });
    }

    // for any file type that has to be shipped with task
    if (externals.hasOwnProperty('files')) {
        var files = externals.files;
        files.forEach(function (file) {
            assert(file.url, 'file.url');
            assert(file.dest, 'file.dest');

            // download the file from url
            var fileSource = downloadFile(file.url);
            // copy the files
            var fileDest = path.join(destRoot, file.dest);
            mkdir('-p', path.dirname(fileDest));
            cp(fileSource, fileDest);
        });
    }
}
exports.getExternals = getExternals;

//------------------------------------------------------------------------------
// task.json functions
//------------------------------------------------------------------------------
var fileToJson = function (file) {
    var jsonFromFile = JSON.parse(fs.readFileSync(file).toString());
    return jsonFromFile;
}
exports.fileToJson = fileToJson;

// Validates the structure of a task.json file.
var validateTask = function (task) {
    if (!task.id || !check.isUUID(task.id)) {
        fail('id is a required guid');
    };

    if (!task.name || !check.isAlphanumeric(task.name)) {
        fail('name is a required alphanumeric string');
    }

    if (!task.friendlyName || !check.isLength(task.friendlyName, 1, 40)) {
        fail('friendlyName is a required string <= 40 chars');
    }

    if (!task.instanceNameFormat) {
        fail('instanceNameFormat is required');
    }
};
exports.validateTask = validateTask;
//------------------------------------------------------------------------------
