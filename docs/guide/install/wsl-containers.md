# Running Lemonade in WSL Containers

[WSL containers](https://learn.microsoft.com/windows/wsl/wsl-container) run the [Lemonade container image](./docker.md) on Windows without Docker. Their `wslc` CLI is part of WSL 2.9.3 and later, so run `wsl --update` to get it, then run the commands below in PowerShell.

`wslc` publishes `-p 13305:13305` on `127.0.0.1` only, so the server is reachable from this machine and not from the network. A container session gets half of the machine's memory by default. [WSL container settings](https://learn.microsoft.com/windows/wsl/wsl-container-settings) change both.

Lemonade installed on Windows uses port 13305 as well. While it is running, `wslc run` fails with `WSAEADDRINUSE`, so choose **Quit Lemonade** from its tray icon first, or publish another port, for example `-p 13306:13305`.

## Run with Default Configuration

```powershell
wslc run -d `
  --name lemonade-server `
  -p 13305:13305 `
  -v lemonade-cache:/opt/lemonade/.cache/huggingface `
  -v lemonade-llama:/opt/lemonade/llama `
  -v lemonade-data:/opt/lemonade/.cache/lemonade `
  -v lemonade-config:/opt/lemonade/.config/lemonade `
  ghcr.io/lemonade-sdk/lemonade-server:latest
```

Once the container is running, verify it's working:

```powershell
curl.exe http://localhost:13305/api/v1/models
```

## Run with GPU Passthrough

`--gpus all` gives the container `/dev/dxg` and WSL's GPU libraries:

```powershell
wslc run -d `
  --name lemonade-server `
  --gpus all `
  -p 13305:13305 `
  -v lemonade-cache:/opt/lemonade/.cache/huggingface `
  -v lemonade-llama:/opt/lemonade/llama `
  -v lemonade-data:/opt/lemonade/.cache/lemonade `
  -v lemonade-config:/opt/lemonade/.config/lemonade `
  ghcr.io/lemonade-sdk/lemonade-server:latest
```

The image includes Dozen, Mesa's driver for Vulkan on Direct3D 12, so llama.cpp's default backend, Vulkan, then runs on the GPU. To confirm, `wslc exec lemonade-server vulkaninfo --summary` lists the GPU as a `Microsoft Direct3D12` device. Dozen is not a conformant Vulkan implementation, and Mesa labels it for testing use.

### Use ROCm on an AMD GPU

ROCm is faster than Vulkan on an AMD GPU. Install the Windows driver that [ROCm for WSL](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/wsl/howto_wsl.html) lists. ROCm itself does not have to be installed in a WSL distribution, because Lemonade downloads its own ROCm runtime. Then make ROCm the default backend for llama.cpp:

```powershell
wslc exec lemonade-server lemonade config set llamacpp.backend=rocm
```

> Note: The first model load downloads the ROCm runtime, several gigabytes, into the `lemonade-data` volume.
