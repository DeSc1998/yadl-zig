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
    1. [tree-sitter parser](#parser)
3. [Build Instructions](#build)
    1. [Prerequisites](#pre)
    2. [Building in Terminal/Shell](#build_sh)
4. [Testing of Code](#testing)
    1. [Unit testing](#unit)
    1. [Testing with pytest](#python)

## Quick Start <a name="quick"></a>

Simply run to build:

```shell
> zig build run -- <files...>
```

This will run the `run`-task defined in `build.zig` and add `<files...>` as arguments.

### tree-sitter parser (optional) <a name="parser"></a>

You can get the [tree-sitter parser](https://github.com/DeSc1998/tree-sitter-yadl) for yadl
for syntax highlighting. \
It is in active development though.

## Build Instructions <a name="build"></a>

### Prerequisites <a name="pre"></a>

- [Zig 0.13.0](https://ziglang.org/download/)

### Building in Terminal/Shell <a name="build_sh"></a>

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

## Testing of Code <a name="testing"></a>

### Unit testing <a name="unit"></a>

Similar to building in the terminal you execute the following for the scala unit tests:

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

Compile at least once with `zig build`.

#### Step 2

> NOTE: This step is optional and only required if the install location is different
> from the default. (see `zig build --help` for custom install location)

The python scripts relies on envirnoment variable to be pointed to the yadl interpreter.

To set the env. var. use:

For Linux:
```sh
export YADL_BIN=zig-out/bin/yadl-linux
```
For Mac:
```sh
export YADL_BIN=zig-out/bin/yadl-mac
```

For Windows (may work, previous ci test failed though):
```powershell
set YADL_BIN=.\\zig-out\\bin\\yadl-win.exe
```

#### Step 3

Finally run pytest:
```sh
pytest test-scripts/
```


