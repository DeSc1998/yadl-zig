# *Y*et *A*nother *D*ata *L*anguage

Yadl is a data querring and processing language.

The main reason why we build this language is to simplify processing and
modifying of data. SQL (most if not all dialects), which is mostly used
for storing and querring data, is not useful for modifying data and most
programming languages usually do not provide functionality for reading and
saving data like csv out of the box.

> NOTE: This project was originally a group affort in a university context.
> After the semester was over I started rewritting yadl in zig and offered
> the rest of the group to contribute but no one did so far.
>
> The original project can be found [here](https://github.com/julianjumper/yadl) mirrored by
> one of the contributers.

# Table of Contents

1. [Quick Start](#quick)
2. [Build Instructions](#build)
    1. [Prerequisites](#pre)
    2. [Building in Terminal/Shell](#build_sh)
    3. [Building in intellij IDEA](#build_idea)
3. [Testing of Code](#testing)
    1. [Unit testing](#unit)
    1. [Testing with pytest](#python)

## Quick Start <a name="quick"></a>

Simply run to build:

```shell
> zig build run -- <files...>
```

This will run the `run`-task defined is `build.zig` and add `<files...>` as arguments.

## Build Instructions <a name="build"></a>

### Prerequisites <a name="pre"></a>

For the zig build:
- [Zig 0.13.0](https://ziglang.org/download/)

For the scala build:
- [Scala 3.X](https://www.scala-lang.org/download/)
- Recent Java SDK (openjdk 22 for example)

### Building in Terminal/Shell <a name="build_sh"></a>

#### Scala

Run the following commands in the project root.

Just building:
```sh
sbt compile
```

Running:
```sh
sbt run
```

Running with Program arguments:
```sh
sbt "run args..."
```

The quotes are neccessary here because otherwise they would be interpreted as a new command from sbt.

#### Zig

Run the following commands in the project root.

Just building:
```sh
zig build
```

Running:
```sh
zig build run
```

Running with Program arguments:
```sh
zig build run -- args...
```

#### Building in intellij IDEA <a name="build_idea"></a>

##### Installing Plugins

install the [Scala Plugin](https://plugins.jetbrains.com/plugin/1347-scala/) from the
jetbrains marketplace.

##### Setting up build tasks

1. When you are in a project go to the top-right where you select your current task and chose 'Edit Configurations...' in the drop-down menu.
2. In the Configuration menu select the `+` to add a new task and chose the 'sbt Task'.
3. Now you can give the task a meaningful name and pick a task to run (for example `run` or `"run args..."` with arguments) among other settings.
4. Once done hit 'Apply' or 'OK' to finish the task setup.

Now you should be able to build/run/package/... the project depending on what you chose as a task.

## Testing of Code <a name="testing"></a>

### Unit testing <a name="unit"></a>

Similar to building in the terminal you execute the following for the scala unit tests:
```sh
sbt test
```

and for the zig unit tests:
```sh
zig build test
```
or for more details:
```sh
zig build test --summary all
```

### Testing with pytest <a name="python"></a>

These tests involve a bit more work to be run.
For the duration of these steps I assume you are at the root of the project.

#### Prerequisites

Install [pytest](https://pypi.org/project/pytest/)

#### Step 1

##### Scala

Similar to building in the terminal you execute the `assembly`-task added by the `project/plugin.sbt` build config:
```sh
sbt assembly
```
This will emit a jar-file which we use in the following steps.

##### Zig

Just compile at least once.

#### Step 2

The python scripts relies on envirnoment variable to be pointed to the yadl interpreter.

To set the env. var. use:

For Linux and Mac:
```sh
export YADL_JAR=target/scala-3.4.1/yadl.jar
export YADL_MAC=zig-out/bin/yadl-mac
export YADL_LINUX=zig-out/bin/yadl-linux
```

For Windows:
```powershell
set YADL_JAR=target/scala-3.4.1/yadl.jar
set YADL_WIN=zig-out/bin/yadl-win.exe
```
#### Step 3

Finally run pytest:
```sh
pytest
```


