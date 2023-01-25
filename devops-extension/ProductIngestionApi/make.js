// parse command line options
var argv = require('minimist')(process.argv.slice(2));

// modules
var fs = require('fs');
var os = require('os');
var path = require('path');
var semver = require('semver');
var util = require('./make-util');
var admzip = require('adm-zip');
const { exit } = require('process');

// util functions
var mkdir = util.mkdir;
var rm = util.rm;
var test = util.test;
var banner = util.banner;
var fail = util.fail;
var ensureExists = util.ensureExists;
var addPath = util.addPath;
var copyTaskResources = util.copyTaskResources;
var copyExtensionResources = util.copyExtensionResources;
var matchCopy = util.matchCopy;
var ensureTool = util.ensureTool;
var getExternals = util.getExternals;
var validateTask = util.validateTask;
var fileToJson = util.fileToJson;

// global paths
var buildPath = path.join(__dirname, '_build');
var buildTasksPath = path.join(__dirname, '_build', 'ProductIngestionApi');
var buildTasksCommonPath = path.join(__dirname, '_build', 'ProductIngestionApi', 'Common');
var tasksPath = __dirname;
var binPath = path.join(__dirname, 'node_modules', '.bin');
var makeOptionsPath = path.join(__dirname, 'make-options.json');

var CLI = {};

// node min version
var minNodeVer = '6.10.3';
if (semver.lt(process.versions.node, minNodeVer)) {
    fail('requires node >= ' + minNodeVer + '.  installed: ' + process.versions.node);
}


// add node modules .bin to the path so we can dictate version of tsc etc...
if (!test('-d', binPath)) {
    fail('node modules bin not found.  ensure npm install has been run.');
}
addPath(binPath);

// resolve list of tasks
var taskList = fileToJson(makeOptionsPath).tasks;

CLI.clean = function() {
    rm('-Rf', buildPath);
    mkdir('-p', buildTasksPath);
};

//
// ex: node make.js build
//
CLI.build = function() {
    CLI.clean();

    ensureTool('npm', '--version', function (output) {
        if (semver.lt(output, '5.6.0')) {
            fail('Expected 5.6.0 or higher. To fix, run: npm install -g npm');
        }
    });

    console.log();
    console.log('> copying module resources');
    copyExtensionResources("./", buildTasksPath);

    taskList.forEach(function(taskName) {
        banner('Building: ' + taskName);
        var taskPath = path.join(tasksPath, taskName);
        ensureExists(taskPath);

        // load the task.json
        var outDir;
        var taskJsonPath = path.join(taskPath, 'task.json');
        if (test('-f', taskJsonPath)) {
            var taskDef = fileToJson(taskJsonPath);
            validateTask(taskDef);

            outDir = path.join(buildTasksPath, taskName);

        } else {
            outDir = path.join(buildTasksPath, path.basename(taskPath));
        }

        mkdir('-p', outDir);

        // get externals
        var taskMakePath = path.join(taskPath, 'make.json');
        var taskMake = test('-f', taskMakePath) ? fileToJson(taskMakePath) : {};
        if (taskMake.hasOwnProperty('externals')) {
            console.log('');
            console.log('> getting task externals');
            getExternals(taskMake.externals, outDir);
        }

        //--------------------------------
        // Common: build, copy, install
        //--------------------------------
        if (taskMake.hasOwnProperty('common')) {
            var common = taskMake['common'];

            common.forEach(function(mod) {
                var modPath = path.join(taskPath, mod['module']);
                var modName = path.basename(modPath);
                var modOutDir = buildTasksCommonPath;

                if (!test('-d', modOutDir)) {
                    banner('Building module ' + modPath, true);

                    mkdir('-p', modOutDir);

                    // copy default resources and any additional resources defined in the module's make.json
                    console.log();
                    console.log('> copying module resources');
                    var modMakePath = path.join(modPath, 'make.json');
                    var modMake = test('-f', modMakePath) ? fileToJson(modMakePath) : {};
                    copyTaskResources(modMake, modPath, modOutDir);
                }

                // copy ps module resources to the task output dir
                if (mod.type === 'ps') {
                    console.log();
                    console.log('> copying ps module to task');
                    var dest;
                    if (mod.hasOwnProperty('dest')) {
                        dest = path.join(outDir, mod.dest, modName);
                    } else {
                        dest = path.join(outDir, 'ps_modules', modName);
                    }

                    matchCopy('!Tests', modOutDir, dest, { noRecurse: true, matchBase: true });
                }
            });

        // copy default resources and any additional resources defined in the task's make.json
        console.log();
        console.log('> copying task resources');
        copyTaskResources(taskMake, taskPath, outDir);
    }
    });

    banner('Build successful', true);
}

var command  = argv._[0];

if (typeof CLI[command] !== 'function') {
  fail('Invalid CLI command: "' + command + '"\r\nValid commands:' + Object.keys(CLI));
}

CLI[command](argv)

