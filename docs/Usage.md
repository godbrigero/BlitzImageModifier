# Basic Usage of This Project

## Dependencies

- Docker Engine (https://www.docker.com/get-started/)
- Make (`brew install make` on macOS)

## Quick Start

```bash
make build-all
# Builds for all devices defined (right now only pi5)
```

## Build for a specific device

```bash
make build-for ARGS=pi5
# Builds for the specific device defined (right now only pi5)
```

The Pi image build creates a login user during image compilation, before the image is exported. Defaults are:

```text
username: ubuntu
password: ubuntu
uid: 1000
gid: 1000
```

You can override the account at build time:

```bash
make build-for pi5 BLITZ_USER=myuser BLITZ_PASSWORD=mypass
make build-for pi5 BLITZ_USER=myuser BLITZ_PASSWORD=mypass BLITZ_UID=1001 BLITZ_GID=1001
```

The generated user owns `/opt/blitz`, so normal user tools can modify file and directory timestamps there without running as root.

## Outputs

The outputs are located in the `outputs/` directory. Usually, the output is a .img file for faster copying.

In order to compress the output, you can use the following command:

```bash
xz -T 0 -v outputs/image_name.img
```
