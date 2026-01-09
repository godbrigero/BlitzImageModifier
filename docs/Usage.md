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

## Outputs

The outputs are located in the `outputs/` directory. Usually, the output is a .img file for faster copying.

In order to compress the output, you can use the following command:

```bash
xz -T 0 -v outputs/image_name.img
```
